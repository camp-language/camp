package codegen

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
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
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

	// Build iovs in memory: [str_ptr, str_len] at address 4096
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	// fd_write(fd=1, iovs=4096, iovs_len=1, nwritten=0)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
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

emit_camp_dealloc_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 16)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

	emit_camp_print_err_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	// Build iovs in memory: [str_ptr, str_len] at address 4096
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	// fd_write(fd=2, iovs=4096, iovs_len=1, nwritten=0)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
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

emit_camp_list_alloc_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	emit_instruction(Wasm_I32_Const{value = 12}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)

	emit_instruction(Wasm_Local_Tee{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	emit_instruction(Wasm_I32_Const{value = 32}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 1}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_list_push_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	// data_ptr + len * 8
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_list_len_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 16)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_list_get_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_str_len_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 16)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_str_eq_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_str_concat_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	// Concatenate two strings.
	// Each string is a pointer to a heap block: [len:4][data...].
	// Returns a pointer to a new heap block.
	// Params: (str_a: i32, str_b: i32) -> i32
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 96)

	// Load len_a
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)

	// Load len_b
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)

	// total_len = len_a + len_b
	emit_instruction(Wasm_I32_Add{}, &buf)

	// Save total_len in local 2
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)

	// Allocate total_len + 4 bytes (4 for length prefix)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)

	// Save result pointer in local 3
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// Store total length at offset 0 of result
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// memory.copy(dest=result+4, src=str_a+4, len=len_a)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_Memory_Copy{}, &buf)

	// memory.copy(dest=result+4+len_a, src=str_b+4, len=len_b)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_Memory_Copy{}, &buf)

	// Return result pointer
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_async_init_body :: proc() -> Wasm_Code {
	// Initialize async scheduler — no-op for now (scheduler state in linear memory)
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_reduce_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_reduce(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, init: i32, chunk_size: i32) -> i32
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 192)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_async_enqueue_body :: proc() -> Wasm_Code {
	// camp_async_enqueue(closure_fn: i32, closure_env: i32) -> i32 (handle_id)
	// Simplified: return closure_fn as handle_id
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 16)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
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
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 192)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Block{block_type = .I32}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_all_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_all(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	// Sequential fallback: iterate items, call fn on each, collect all results.
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_HEADER_SIZE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
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
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_async_dequeue_body :: proc() -> Wasm_Code {
	// camp_async_dequeue() -> i32 (closure_fn, 0 = empty)
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
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
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

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

	emit_instruction(Wasm_End{}, &buf)

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
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[4] = Wasm_Local_Decl{count = 1, type = .I32}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_async_run_body :: proc() -> Wasm_Code {
	// camp_async_run() -> i32 (exit code)
	// Simplified: return 0
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
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

emit_camp_sched_init_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BASE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_spawn_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)
	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_PENDING}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 20}, &buf)
	global_queue_base := handle_table_base + SCHED_HANDLE_TABLE_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Notify{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_complete_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)
	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_COMPLETED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)
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
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_join_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)
	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Block{block_type = .I32}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	// Check COMPLETED: if status == COMPLETED, load result and branch out
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_COMPLETED}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_Br{label = 2}, &buf) // branch out of block i32 with result
	emit_instruction(Wasm_End{}, &buf)
	// Check CANCELLED: if status == CANCELLED, return 0 and branch out
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_CANCELLED}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Br{label = 2}, &buf) // branch out of block i32 with 0
	emit_instruction(Wasm_End{}, &buf)
	// Wait: sleep until notification counter changes
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	// After loop (unreachable): store JOINED and load result
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_JOINED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_cancel_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)
	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_CANCELLED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
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
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_yield_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_block_io_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)
	wait_map_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE + SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_WAIT_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_timer_insert_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)
	timer_wheel_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE + SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE + SCHED_JOIN_MAP_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 64}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 6}, &buf)
	emit_instruction(Wasm_I32_Shr_U{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 262144}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 12}, &buf)
	emit_instruction(Wasm_I32_Shr_U{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 3}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 18}, &buf)
	emit_instruction(Wasm_I32_Shr_U{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 63}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	timer_pool_base := timer_wheel_base + SCHED_TIMER_WHEEL_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_TIMER_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base + 8)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 64}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 7)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I64}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I64}
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[4] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[5] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[6] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_timer_cancel_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)
	timer_wheel_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE + SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE + SCHED_JOIN_MAP_SIZE
	timer_pool_base := timer_wheel_base + SCHED_TIMER_WHEEL_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_TIMER_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_notify_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)
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
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_park_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 64)
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_worker_loop_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 512)
	handle_table_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	global_queue_base := handle_table_base + SCHED_HANDLE_TABLE_SIZE
	timer_wheel_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE + SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE + SCHED_JOIN_MAP_SIZE
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 3}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_SCHED_YIELD)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Atomic_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_Memory_Atomic_Wait32{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Atomic_RMW_Add{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 8)
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[4] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[5] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[6] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[7] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_map_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_map(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_HEADER_SIZE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(runtime_indices[Runtime_Func.Alloc])}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_TAG_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store8{offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
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
	locals[0] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[1] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[2] = Wasm_Local_Decl{count = 1, type = .I32}
	locals[3] = Wasm_Local_Decl{count = 1, type = .I32}
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_i64_to_str_body :: proc() -> Wasm_Code {
	// camp_i64_to_str(val: i64) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_i32_to_str_body :: proc() -> Wasm_Code {
	// camp_i32_to_str(val: i32) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_f64_to_str_body :: proc() -> Wasm_Code {
	// camp_f64_to_str(val: f64) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_bool_to_str_body :: proc() -> Wasm_Code {
	// camp_bool_to_str(val: i32) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf { body[i] = b }
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}