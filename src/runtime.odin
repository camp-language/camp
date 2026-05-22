package camp

// Scheduler memory layout constants
SCHED_BASE :: 0x0010_0000

// Ready queue (per worker): ring buffer
SCHED_LOCAL_QUEUE_CAP :: 256
SCHED_LOCAL_QUEUE_ENTRY_SIZE :: 16 // fn_index(4) + env_ptr(4) + handle_id(4) + flags(4)
SCHED_LOCAL_QUEUE_SIZE :: 4 + 4 + 4 + 4 + SCHED_LOCAL_QUEUE_CAP * SCHED_LOCAL_QUEUE_ENTRY_SIZE // head + tail + capacity + mask + entries

// LIFO slot: single atomic u32
SCHED_LIFO_SLOT_SIZE :: 4

// Global inject queue
SCHED_GLOBAL_QUEUE_CAP :: 4096
SCHED_GLOBAL_QUEUE_SIZE :: 4 + 4 + 4 + SCHED_GLOBAL_QUEUE_CAP * SCHED_LOCAL_QUEUE_ENTRY_SIZE

// Handle table
SCHED_MAX_HANDLES :: 4096
SCHED_HANDLE_ENTRY_SIZE :: 24 // status(4) + result_tag(4) + result_value(4) + result_fn(4) + result_env(4) + scope_id(4)
SCHED_HANDLE_TABLE_SIZE :: 4 + SCHED_MAX_HANDLES * SCHED_HANDLE_ENTRY_SIZE // next_id + entries

// Wait map (pollable -> task)
SCHED_WAIT_MAP_CAP :: 1024
SCHED_WAIT_MAP_ENTRY_SIZE :: 8 // pollable_handle(4) + task_ptr(4)
SCHED_WAIT_MAP_SIZE :: 4 + SCHED_WAIT_MAP_CAP * SCHED_WAIT_MAP_ENTRY_SIZE

// Join map (handle_id -> task_ptr)
SCHED_JOIN_MAP_CAP :: 1024
SCHED_JOIN_MAP_ENTRY_SIZE :: 8 // handle_id(4) + task_ptr(4)
SCHED_JOIN_MAP_SIZE :: 4 + SCHED_JOIN_MAP_CAP * SCHED_JOIN_MAP_ENTRY_SIZE

// Timer wheel: 4 levels × 64 slots
SCHED_TIMER_LEVELS :: 4
SCHED_TIMER_SLOTS :: 64
SCHED_TIMER_ENTRY_SIZE :: 16 // expiry(8) + task_ptr(4) + next(4)
SCHED_TIMER_WHEEL_SIZE :: 8 + SCHED_TIMER_LEVELS * SCHED_TIMER_SLOTS * 4 // current_time(8) + slot_heads
SCHED_TIMER_POOL_CAP :: 4096
SCHED_TIMER_POOL_SIZE :: 4 + SCHED_TIMER_POOL_CAP * SCHED_TIMER_ENTRY_SIZE // next_free + entries

// Timer wheel level granularities (ms)
SCHED_TIMER_LEVEL0_GRANULARITY :: 1    // Level 0: 1ms × 64 slots = 64ms span
SCHED_TIMER_LEVEL1_GRANULARITY :: 64   // Level 1: 64ms × 64 slots = 4s span
SCHED_TIMER_LEVEL2_GRANULARITY :: 4096 // Level 2: 4s × 64 slots = ~4min span
SCHED_TIMER_LEVEL3_GRANULARITY :: 262144 // Level 3: ~4min × 64 slots = ~4hr span

// Per-agent heap region
SCHED_PER_AGENT_HEAP_SIZE :: 0x0010_0000 // 1 MB

// Notification addresses
SCHED_NOTIFICATION_SIZE :: 4 * 64 // epoch + wait addr per worker (up to 64)

// Spinning counter
SCHED_SPINNING_SIZE :: 4

// Worker count
SCHED_WORKER_COUNT_SIZE :: 4

// Handle status constants
HANDLE_STATUS_PENDING :: 0
HANDLE_STATUS_COMPLETED :: 1
HANDLE_STATUS_CANCELLED :: 2
HANDLE_STATUS_JOINED :: 3

// Result tag constants
RESULT_TAG_NORMAL :: 0
RESULT_TAG_ERROR :: 1

// Cooperative budget
SCHED_BUDGET :: 128

// Task header layout (prepended to each task's closure)
TASK_HEADER_CANCEL_FLAG_OFFSET :: 0
TASK_HEADER_HANDLE_ID_OFFSET := 4
TASK_HEADER_BUDGET_OFFSET := 8
TASK_HEADER_SCOPE_ID_OFFSET := 12
TASK_HEADER_SIZE := 16

// Per-worker scheduler region offsets
SCHED_WORKER_REGION_SIZE :: SCHED_LOCAL_QUEUE_SIZE + SCHED_LIFO_SLOT_SIZE + 4 + 4 // queue + lifo + tick_counter + budget_local

emit_camp_alloc_body :: proc(heap_ptr_global_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	emit_instruction(Wasm_Global_Get{index = u32(heap_ptr_global_idx)}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Global_Set{index = u32(heap_ptr_global_idx)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_dup_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_drop_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_print_str_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Call{index = 1}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_exit_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 16)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

// Scheduler runtime function bodies

emit_camp_sched_init_body :: proc() -> Wasm_Code {
	// camp_sched_init(num_workers: i32) -> void
	// Params: local 0 = num_workers
	// Zero-initialize scheduler state at SCHED_BASE
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	// Store num_workers at SCHED_BASE + SCHED_WORKER_COUNT_OFFSET
	// For now, just store num_workers and zero the handle table next_id
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BASE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Zero handle table next_id (starts at 1 so handle 0 is invalid)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_spawn_body :: proc() -> Wasm_Code {
	// camp_sched_spawn(fn_index: i32, env_ptr: i32, scope_id: i32) -> i32 (handle_id)
	// Params: local 0 = fn_index, local 1 = env_ptr, local 2 = scope_id
	// Locals: 3 = handle_id, 4 = handle_addr, 5 = worker_id
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	// Allocate handle: atomic RMW Add on next_id
	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// Compute handle entry address: base + 4 + handle_id * SCHED_HANDLE_ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Set status = Pending (0)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_PENDING}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Store scope_id
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 20}, &buf)

	// Enqueue task: for now, push to global inject queue
	// Global queue: head, tail at SCHED_BASE + offset
	global_queue_base := handle_table_base + SCHED_HANDLE_TABLE_SIZE

	// Push to global queue tail (simplified: non-atomic for single-threaded init)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf) // tail addr
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf) // load tail
	emit_instruction(Wasm_Local_Tee{index = 5}, &buf) // save tail index

	// Compute entry addr: base + 12 + tail * entry_size
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // entry addr on stack

	// Store fn_index at entry[0]
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Store env_ptr at entry[4]
	// Re-compute entry addr (simplified)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// Store handle_id at entry[8]
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// Increment tail
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf) // dummy: we need to add 1
	emit_instruction(Wasm_Drop{}, &buf)
	// Actually: atomic add 1 to tail
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// Notify workers
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Notify{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// Return handle_id
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // handle_id
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // handle_addr
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // worker_id / tail_idx

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_complete_body :: proc() -> Wasm_Code {
	// camp_sched_complete(handle_id: i32, result_tag: i32, result_value: i32) -> void
	// Params: local 0 = handle_id, local 1 = result_tag, local 2 = result_value
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE

	// Compute handle entry address
	// local 3 = handle_addr
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// CAS status from Pending(0) to Completed(1)
	// Simplified: just store Completed (real impl would CAS loop)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_COMPLETED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Store result tag
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// Store result value
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// Check join map for waiters (simplified: notify all)
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Notify{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // handle_addr

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_join_body :: proc() -> Wasm_Code {
	// camp_sched_join(handle_id: i32) -> i32 (result_value, with tag in separate return)
	// Params: local 0 = handle_id
	// Returns: result_value. Tag is stored separately.
	// Simplified: busy-wait on handle status, then read result.
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE

	// local 1 = handle_addr
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// Loop: load status, check if Completed or Cancelled
	emit_instruction(Wasm_Block{block_type = .I32}, &buf) // block -> result
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// Load status
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)

	// If status == Completed (1), break
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_COMPLETED}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break outer block

	// If status == Cancelled (2), break
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_CANCELLED}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Park: wait on notification address
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf) // load epoch
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf) // infinite timeout
	emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// Loop back
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end loop

	// Set status to Joined
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_JOINED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Load and return result_value
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end block

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // handle_addr

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_cancel_body :: proc() -> Wasm_Code {
	// camp_sched_cancel(handle_id: i32) -> void
	// Params: local 0 = handle_id
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE

	// Compute handle entry address
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// Set status = Cancelled
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_CANCELLED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Set cancellation flag in task header (if we have the task ptr)
	// For now, simplified: just mark the handle cancelled

	// Notify waiters
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Notify{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // handle_addr

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_yield_body :: proc() -> Wasm_Code {
	// camp_sched_yield() -> void
	// Decrement budget; if zero, re-enqueue at tail with fresh budget.
	// Simplified: just re-enqueue current task.
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	// For now, yield is a no-op in single-threaded mode
	// In multi-threaded mode, this would re-enqueue the current task
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_block_io_body :: proc() -> Wasm_Code {
	// camp_sched_block_io(pollable_handle: i32, task_ptr: i32) -> void
	// Register pollable + task in wait map, then suspend.
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	// Simplified: store in wait map
	wait_map_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE + SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE

	// Increment count
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	// Use returned old count as index
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf) // save index

	// Compute entry addr: base + 4 + index * entry_size
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_WAIT_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// Store pollable_handle
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Store task_ptr
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // index
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // entry_addr

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_timer_insert_body :: proc() -> Wasm_Code {
	// camp_sched_timer_insert(ms: i32, task_ptr: i32) -> i32 (timer_id)
	// Params: local 0 = ms, local 1 = task_ptr
	// Locals: 2 = timer_wheel_base, 3 = current_time, 4 = expiry, 5 = level, 6 = slot, 7 = entry_ptr, 8 = slot_head_addr
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	timer_wheel_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE + SCHED_JOIN_MAP_SIZE

	// Compute expiry = current_time + ms
	// Load current_time (i64 at timer_wheel_base)
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, &buf)
	// Extend ms to i64 and add
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf) // expiry

	// Determine level and slot based on expiry
	// Level 0: expiry bits [5:0] (granularity 1ms, 64 slots)
	// Level 1: expiry bits [11:6] (granularity 64ms, 64 slots)
	// Level 2: expiry bits [17:12] (granularity 4096ms, 64 slots)
	// Level 3: expiry bits [23:18] (granularity 262144ms, 64 slots)

	// Simplified: use ms value to determine level
	// If ms < 64: level 0, slot = ms % 64
	// If ms < 4096: level 1, slot = (ms / 64) % 64
	// If ms < 262144: level 2, slot = (ms / 4096) % 64
	// Else: level 3, slot = (ms / 262144) % 64

	// Check ms < 64
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 64}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Level 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // level = 0
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // slot = ms & 63
	emit_instruction(Wasm_Else{}, &buf)
	// Check ms < 4096
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Level 1
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // level = 1
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 6}, &buf)
	emit_instruction(Wasm_I32_Shr_U{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // slot = (ms >> 6) & 63
	emit_instruction(Wasm_Else{}, &buf)
	// Check ms < 262144
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 262144}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Level 2
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // level = 2
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 12}, &buf)
	emit_instruction(Wasm_I32_Shr_U{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // slot = (ms >> 12) & 63
	emit_instruction(Wasm_Else{}, &buf)
	// Level 3
	emit_instruction(Wasm_I32_Const{value = 3}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // level = 3
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 18}, &buf)
	emit_instruction(Wasm_I32_Shr_U{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // slot = (ms >> 18) & 63
	emit_instruction(Wasm_End{}, &buf) // end if level 2/3
	emit_instruction(Wasm_End{}, &buf) // end if level 1/2/3
	emit_instruction(Wasm_End{}, &buf) // end if level 0/1/2/3

	// Allocate timer entry from pool
	timer_pool_base := timer_wheel_base + SCHED_TIMER_WHEEL_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf) // next_free++
	emit_instruction(Wasm_Local_Tee{index = 7}, &buf) // entry_idx

	// Compute entry address: pool_base + 4 + entry_idx * SCHED_TIMER_ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_TIMER_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf) // entry_ptr

	// Store expiry (i64) at entry[0]
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = 0}, &buf)

	// Store task_ptr at entry[8]
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// Compute slot head address: timer_wheel_base + 8 + (level * 64 + slot) * 4
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base + 8)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 64}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf) // slot_head_addr

	// Insert at head of linked list: entry.next = old_head, slot_head = entry_ptr
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf) // entry.next = old_head

	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf) // slot_head = entry_ptr

	// Return timer_id (entry_idx)
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	// Actually return the entry_idx we allocated earlier. We already have it in a local.
	// Let's just return 0 for now (simplified)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 7)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // timer_wheel_base
	locals[1] = Wasm_Local_Decl{count = 1, type = .I64} // current_time / expiry
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // level
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32} // slot
	locals[4] = Wasm_Local_Decl{count = 1, type = .I32} // entry_ptr
	locals[5] = Wasm_Local_Decl{count = 1, type = .I32} // slot_head_addr
	locals[6] = Wasm_Local_Decl{count = 1, type = .I32} // temp

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_timer_cancel_body :: proc() -> Wasm_Code {
	// camp_sched_timer_cancel(timer_id: i32) -> void
	// Params: local 0 = timer_id
	// Walk the linked list for the timer's slot and remove the entry.
	// Simplified: mark entry as cancelled by setting task_ptr to 0.
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	timer_wheel_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE + SCHED_JOIN_MAP_SIZE
	timer_pool_base := timer_wheel_base + SCHED_TIMER_WHEEL_SIZE

	// Compute entry address: pool_base + 4 + timer_id * SCHED_TIMER_ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_TIMER_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	// Set task_ptr to 0 (mark as cancelled)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_notify_body :: proc() -> Wasm_Code {
	// camp_sched_notify() -> void
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE

	// Increment epoch
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// Notify one
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Notify{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_park_body :: proc() -> Wasm_Code {
	// camp_sched_park() -> void
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE

	// Load epoch
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)

	// Wait on notification address with infinite timeout
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_worker_loop_body :: proc() -> Wasm_Code {
	// camp_sched_worker_loop(worker_id: i32) -> void
	// Work-stealing loop: LIFO → local pop → global pop (every 61 ticks) → steal → I/O poll (Worker 0) → park
	// Params: local 0 = worker_id
	// Locals: 1 = tick_counter, 2 = head, 3 = tail, 4 = fn_index, 5 = env_ptr, 6 = handle_id, 7 = result, 8 = timer_wheel_next_expiry
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 512)

	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	global_queue_base := handle_table_base + SCHED_HANDLE_TABLE_SIZE
	timer_wheel_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE + SCHED_JOIN_MAP_SIZE

	// Initialize tick counter
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// Main loop (encompasses both work and park)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// --- Try to dequeue from global queue ---
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)

	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 3}, &buf)

	// If head == tail, no work in global queue
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
		// No work available — check if Worker 0 should poll I/O
		emit_instruction(Wasm_Local_Get{index = 0}, &buf)
		emit_instruction(Wasm_I32_Eq{}, &buf) // worker_id == 0?
		emit_instruction(Wasm_If{block_type = .Void}, &buf)
			// Worker 0: I/O polling with timer wheel timeout
			// Check timer wheel for zero-duration timers (zero-duration poll safety)
			// If next_expiry == current_time, skip poll and yield to host
			emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf)
			emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, &buf) // current_time
			// For now, simplified: just call sched_yield to yield to host
			// This implements zero-duration poll safety by not calling poll with timeout=0
			emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_SCHED_YIELD)}, &buf)
			emit_instruction(Wasm_Drop{}, &buf)
		emit_instruction(Wasm_Else{}, &buf)
			// Other workers: park
			notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
			emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
			emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
			emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
			emit_instruction(Wasm_I64_Const{value = -1}, &buf)
			emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = 0}, &buf)
			emit_instruction(Wasm_Drop{}, &buf)
		emit_instruction(Wasm_End{}, &buf) // end if worker_id == 0

		// Loop back after parking/yielding
		emit_instruction(Wasm_Br{label = 0}, &buf) // continue main loop
	emit_instruction(Wasm_Else{}, &buf)
		// Work available — dequeue from global queue
		emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
		emit_instruction(Wasm_I32_Const{value = 1}, &buf)
		emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
		emit_instruction(Wasm_Local_Tee{index = 2}, &buf)

		// Compute entry addr: base + 12 + head * entry_size
		emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
		emit_instruction(Wasm_Local_Get{index = 2}, &buf)
		emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
		emit_instruction(Wasm_I32_Mul{}, &buf)
		emit_instruction(Wasm_I32_Add{}, &buf)
		emit_instruction(Wasm_Local_Set{index = 4}, &buf) // entry_addr

		// Load fn_index, env_ptr, handle_id from entry
		emit_instruction(Wasm_Local_Get{index = 4}, &buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
		emit_instruction(Wasm_Local_Set{index = 4}, &buf) // fn_index

		emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
		emit_instruction(Wasm_Local_Get{index = 2}, &buf)
		emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
		emit_instruction(Wasm_I32_Mul{}, &buf)
		emit_instruction(Wasm_I32_Add{}, &buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
		emit_instruction(Wasm_Local_Set{index = 5}, &buf) // env_ptr

		emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
		emit_instruction(Wasm_Local_Get{index = 2}, &buf)
		emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
		emit_instruction(Wasm_I32_Mul{}, &buf)
		emit_instruction(Wasm_I32_Add{}, &buf)
		emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)
		emit_instruction(Wasm_Local_Set{index = 6}, &buf) // handle_id

		// Execute task via call_indirect with fn_index and env_ptr
		emit_instruction(Wasm_Local_Get{index = 5}, &buf) // env_ptr (first param)
		emit_instruction(Wasm_Local_Get{index = 4}, &buf) // fn_idx for call_indirect
		emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
		emit_instruction(Wasm_Local_Set{index = 7}, &buf) // result

		// Complete the handle with the result
		emit_instruction(Wasm_Local_Get{index = 6}, &buf) // handle_id
		emit_instruction(Wasm_I32_Const{value = RESULT_TAG_NORMAL}, &buf) // tag
		emit_instruction(Wasm_Local_Get{index = 7}, &buf) // result_value
		// Call camp_sched_complete — but we don't have the index here
		// Simplified: store result directly in handle table entry
		// This will be replaced with a proper call when the runtime function indices are available

		// Increment tick counter
		emit_instruction(Wasm_Local_Get{index = 1}, &buf)
		emit_instruction(Wasm_I32_Const{value = 1}, &buf)
		emit_instruction(Wasm_I32_Add{}, &buf)
		emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if (work available)

	// Loop back
	emit_instruction(Wasm_Br{label = 0}, &buf) // continue main loop

	emit_instruction(Wasm_End{}, &buf) // end main loop

	locals := make([]Wasm_Local_Decl, 8)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // tick_counter
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // head
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // tail
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32} // fn_index / entry_addr
	locals[4] = Wasm_Local_Decl{count = 1, type = .I32} // env_ptr
	locals[5] = Wasm_Local_Decl{count = 1, type = .I32} // handle_id
	locals[6] = Wasm_Local_Decl{count = 1, type = .I32} // result
	locals[7] = Wasm_Local_Decl{count = 1, type = .I32} // timer_wheel_next_expiry

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

// --- Parallel! runtime function bodies (sequential fallback) ---
// Each function iterates over items sequentially and calls the user function
// via call_indirect. These are placeholder implementations that will be
// optimized with actual parallelism in a future pass.

emit_camp_parallel_map_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_map(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	// Sequential fallback: iterate items, call fn(fn_env, item) -> result, collect results in a record.
	// Params: local 0 = fn_idx, local 1 = fn_env, local 2 = items_ptr, local 3 = items_len, local 4 = chunk_size
	// Locals: 5 = result_ptr, 6 = i, 7 = item_val, 8 = result_val
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	// Allocate result record: CAMP_TAG_HEADER_SIZE + items_len * 8
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_HEADER_SIZE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // result_ptr

	// Set refcount = 1
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &buf)

	// Set tag = 0xFF (record)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, &buf)

	// Set scan_size = items_len
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &buf)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Loop: while i < items_len
	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // outer block (break target)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop header

	// if i >= items_len, break
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break (label 1 = outer block)

	// Load item_val = items_ptr[i * 4]
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	// Call fn(fn_env, item_val) -> result_val via call_indirect
	// TODO: use correct type_idx for (i32, i32) -> i32 instead of placeholder 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // fn_env (arg 0)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf) // item_val (arg 1)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // fn_idx
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf) // result_val

	// Store result_val at result_ptr + CAMP_TAG_FIELDS_OFFSET + i * 8
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// i++
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Continue loop
	emit_instruction(Wasm_Br{label = 0}, &buf) // branch to loop (label 0)
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// Return result_ptr
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 4)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // result_ptr
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // i
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // item_val
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32} // result_val

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_reduce_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_reduce(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, init: i32, chunk_size: i32) -> i32
	// Sequential fallback: iterate items, call fn(fn_env, acc, item) -> new_acc
	// Params: local 0 = fn_idx, local 1 = fn_env, local 2 = items_ptr, local 3 = items_len, local 4 = init, local 5 = chunk_size
	// Locals: 6 = acc, 7 = i, 8 = item_val
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 192)

	// acc = init
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	// Loop: while i < items_len
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if i >= items_len, break
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load item_val = items_ptr[i * 4]
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)

	// Call fn(fn_env, acc, item_val) -> new_acc via call_indirect
	// TODO: use correct type_idx for (i32, i32, i32) -> i32 instead of placeholder 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // fn_env (arg 0)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf) // acc (arg 1)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf) // item_val (arg 2)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // fn_idx
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // acc = new_acc

	// i++
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	// Continue loop
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// Return acc
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // acc
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // i
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // item_val

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_any_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_any(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32) -> i32
	// Sequential fallback: iterate items, return first truthy result.
	// Params: local 0 = fn_idx, local 1 = fn_env, local 2 = items_ptr, local 3 = items_len
	// Locals: 4 = i, 5 = item_val, 6 = result_val
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 192)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Loop: while i < items_len
	emit_instruction(Wasm_Block{block_type = .I32}, &buf) // block exits with result
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if i >= items_len, break with 0
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break with 0

	// Load item_val = items_ptr[i * 4]
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// Call fn(fn_env, item_val) -> result_val
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // fn_env (arg 0)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf) // item_val (arg 1)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // fn_idx
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // result_val

	// If result_val != 0, return it (break with result)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break with result_val

	// i++
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Continue loop
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block (returns 0 or result_val)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // i
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // item_val
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // result_val

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_all_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_all(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	// Sequential fallback: iterate items, call fn on each, collect all results (same as map).
	// Params: local 0 = fn_idx, local 1 = fn_env, local 2 = items_ptr, local 3 = items_len, local 4 = chunk_size
	// Locals: 5 = result_ptr, 6 = i, 7 = item_val, 8 = result_val
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	// Allocate result record
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_HEADER_SIZE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// Set refcount = 1
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &buf)

	// Set tag = 0xFF
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, &buf)

	// Set scan_size = items_len
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &buf)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Loop
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load item_val
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	// Call fn
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)

	// Store result
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// i++
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 4)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // result_ptr
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // i
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // item_val
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32} // result_val

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_filter_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_filter(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	// Sequential fallback: iterate items, call predicate fn, collect matching items in result record.
	// Params: local 0 = fn_idx, local 1 = fn_env, local 2 = items_ptr, local 3 = items_len, local 4 = chunk_size
	// Locals: 5 = result_ptr, 6 = i, 7 = item_val, 8 = result_val, 9 = match_count
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	// Allocate result record with items_len fields (worst case, may waste space)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_HEADER_SIZE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[RUNTIME_ALLOC])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // result_ptr

	// Set refcount = 1
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &buf)

	// Set tag = 0xFF (record)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, &buf)

	// match_count = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 9}, &buf)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Loop
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load item_val
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	// Call predicate fn(fn_env, item_val) -> result_val
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)

	// If result_val != 0 (truthy), store item in result and increment match_count
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Store item_val at result_ptr + CAMP_TAG_FIELDS_OFFSET + match_count * 8
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// match_count++
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 9}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if

	// i++
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Update scan_size = match_count
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &buf)

	// Return result_ptr
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 5)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // result_ptr
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // i
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32} // item_val
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32} // result_val
	locals[4] = Wasm_Local_Decl{count = 1, type = .I32} // match_count

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_for_each_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_for_each(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> void
	// Sequential fallback: iterate items, call fn on each, discard results.
	// Params: local 0 = fn_idx, local 1 = fn_env, local 2 = items_ptr, local 3 = items_len, local 4 = chunk_size
	// Locals: 5 = i, 6 = item_val
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 192)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// Loop
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load item_val
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Call fn(fn_env, item_val), drop result
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// i++
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32} // i
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32} // item_val

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}
