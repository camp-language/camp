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
SCHED_TIMER_LEVEL0_GRANULARITY :: 1 // Level 0: 1ms × 64 slots = 64ms span
SCHED_TIMER_LEVEL1_GRANULARITY :: 64 // Level 1: 64ms × 64 slots = 4s span
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
// Per-worker scheduler region offsets
SCHED_WORKER_REGION_SIZE :: SCHED_LOCAL_QUEUE_SIZE + SCHED_LIFO_SLOT_SIZE + 4 + 4 + 4 // queue + lifo + tick_counter + budget_local + current_task
SCHED_PER_WORKER_START ::
	SCHED_BASE +
	SCHED_WORKER_COUNT_SIZE +
	SCHED_SPINNING_SIZE +
	SCHED_NOTIFICATION_SIZE +
	SCHED_HANDLE_TABLE_SIZE +
	SCHED_GLOBAL_QUEUE_SIZE +
	SCHED_WAIT_MAP_SIZE +
	SCHED_JOIN_MAP_SIZE +
	SCHED_TIMER_WHEEL_SIZE +
	SCHED_TIMER_POOL_SIZE
SCHED_CURRENT_TASK_OFFSET :: SCHED_LOCAL_QUEUE_SIZE + SCHED_LIFO_SLOT_SIZE + 4 + 4 // after local queue + LIFO slot + tick_counter + budget_local

emit_camp_alloc_body :: proc(heap_ptr_global_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)

	emit_instruction(Wasm_Global_Get{index = u32(heap_ptr_global_idx)}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Global_Set{index = u32(heap_ptr_global_idx)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_dup_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)

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

emit_camp_drop_body :: proc(
	drop_func_idx: int,
	dealloc_func_idx: int,
	report_drop_overflow_func_idx: int,
) -> Wasm_Code {
	// camp_drop(ptr: i32, depth: i32)
	// Locals: 2 = new_refcount, 3 = scan_size, 4 = i, 5 = field_value
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XL)

	// Load refcount, decrement, store back
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Check if new refcount == 0
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Check depth overflow
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 256}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call{index = u32(report_drop_overflow_func_idx)}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Load scan_size at ptr + 5
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = 5}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Loop over fields
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load field value at ptr + 8 + i*8
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 5}, &buf)

	// If non-zero, recursive drop
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(drop_func_idx)}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// i++
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)

	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Dealloc: camp_dealloc(ptr, size) where size = 8 + scan_size * 8
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_HEADER_SIZE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(dealloc_func_idx)}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 4,
		type  = .I32,
	}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_report_drop_overflow_body :: proc(msg_offset: u32) -> Wasm_Code {
	// camp_report_drop_overflow(ptr: i32)
	// Writes error message to stderr (fd=2) and exits with code 1
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	// Build iovs in memory: [str_ptr, str_len] at address 4096
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(msg_offset)}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(len("camp_drop: recursion overflow\n"))}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// fd_write(fd=2, iovs=4096, iovs_len=1, nwritten=0)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Call{index = 1}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// proc_exit(1)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Call{index = 0}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)
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
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

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
	buf = make([dynamic]u8, 0, CODE_BUF_TINY)

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
	buf = make([dynamic]u8, 0, CODE_BUF_TINY)

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
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

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
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)

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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_list_push_body :: proc(list_grow_func_idx: int) -> Wasm_Code {
	// Push element to list. Grows capacity if full.
	// Params: (list_ptr: i32, value: i32) -> i32 (returns list_ptr)
	// List layout: [len:4][capacity:4][data_ptr:4]
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	// Check if len >= capacity — if so, grow
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_I32_Ge_U{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Call{index = u32(list_grow_func_idx)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Store value at data_ptr + len * 8
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Increment length
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Return list_ptr
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
	buf = make([dynamic]u8, 0, CODE_BUF_TINY)

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
	// Get element at index from list.
	// Params: (list_ptr: i32, index: i32) -> i32
	// List layout: [len:4][capacity:4][data_ptr:4][data...]
	// Bounds check: if index >= length, trap
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	// Bounds check: if index >= length, unreachable
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Ge_U{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Load data_ptr
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)

	// Add index * 8
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	// Load value
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

emit_camp_list_grow_body :: proc(alloc_func_idx: int, dealloc_func_idx: int) -> Wasm_Code {
	// Grow list capacity when full. Doubles capacity, copies data.
	// Params: (list_ptr: i32) -> i32 (returns list_ptr)
	// List layout: [len:4][capacity:4][data_ptr:4]
	// Locals: 1=old_cap, 2=new_cap, 3=new_data_ptr, 4=old_data_ptr
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	// Load old capacity
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 1}, &buf)

	// new_cap = old_cap * 2 (or 4 if old_cap was 0)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)

	// If new_cap == 0, set to 4
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Allocate new data block: new_cap * 8 bytes
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// Load old data_ptr (local.set, not tee — every later use reloads from local 4)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// memory.copy(new_data_ptr, old_data_ptr, old_cap * 8)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)

	emit_instruction(Wasm_Local_Get{index = 4}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)

	emit_instruction(Wasm_Memory_Copy{}, &buf)

	// Dealloc old data block: dealloc(old_data_ptr, old_cap * 8)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_Call{index = u32(dealloc_func_idx)}, &buf)

	// Update data_ptr
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// Update capacity
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// Return list_ptr
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 4)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // old_cap
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // new_cap
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // new_data_ptr
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // old_data_ptr

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_str_len_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_TINY)

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
	// Compare two strings by length then byte-by-byte.
	// Params: (str_a: i32, str_b: i32) -> i32 (1=equal, 0=not equal)
	// Locals: 2=len_a, 3=len_b, 4=i
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	// Load lengths and compare
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 3}, &buf)
	emit_instruction(Wasm_I32_Ne{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Inner block for "equal" exit
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if i >= len_a, break (equal)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load byte_a
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = 4}, &buf)

	// Load byte_b
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = 4}, &buf)

	// If byte_a != byte_b, return 0 (not equal)
	emit_instruction(Wasm_I32_Ne{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// i++
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// All bytes matched
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // len_a (local 2)
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // len_b (local 3)
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // i (local 4)

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
	buf = make([dynamic]u8, 0, CODE_BUF_MEDIUM)

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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_str_slice_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	// Slice a string: camp_str_slice(str_ptr, start, end) -> str_ptr
	// String layout: [len:4][data...]
	// Returns new string with data from start..end (byte offsets into data)
	// Locals: 3=slice_len, 4=result_ptr
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MEDIUM)

	// slice_len = end - start
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 3}, &buf)

	// Allocate slice_len + 4 bytes (4 for length prefix)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Store slice_len at offset 0 of result
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// memory.copy(dest=result+4, src=str_ptr+4+start, len=slice_len)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)

	emit_instruction(Wasm_Memory_Copy{}, &buf)

	// Return result pointer
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // slice_len
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // result_ptr

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
	buf = make([dynamic]u8, 0, CODE_BUF_LARGE)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
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
	buf = make([dynamic]u8, 0, CODE_BUF_LARGE)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Block{block_type = .I32}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
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
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
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
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
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
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

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
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[4] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}

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
	buf = make([dynamic]u8, 0, CODE_BUF_LARGE)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// Loop
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // i
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // item_val

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_init_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SECTION)

	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	global_queue_base := handle_table_base + SCHED_HANDLE_TABLE_SIZE
	wait_map_base := global_queue_base + SCHED_GLOBAL_QUEUE_SIZE
	join_map_base := wait_map_base + SCHED_WAIT_MAP_SIZE
	timer_wheel_base := join_map_base + SCHED_JOIN_MAP_SIZE
	timer_pool_base := timer_wheel_base + SCHED_TIMER_WHEEL_SIZE

	// If worker_id == 0, initialize global state
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // worker_id
	emit_instruction(Wasm_I32_Eqz{}, &buf) // worker_id == 0?
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// handle_table next_id = 1
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// global_queue head = 0, tail = 0
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf) // head
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf) // tail

	// wait_map next_free = 0
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// join_map next_free = 0
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// timer_pool next_free = 0
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Seed timer wheel current_time via clock_time_get
	// clock_time_get(clock_id=1_MONOTONIC, precision=0_i64, out_ptr=timer_wheel_base) -> errno
	emit_instruction(Wasm_I32_Const{value = 1}, &buf) // CLOCK_MONOTONIC
	emit_instruction(Wasm_I64_Const{value = 0}, &buf) // precision
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf) // out_ptr
	emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_CLOCK_TIME_GET)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf) // drop errno

	emit_instruction(Wasm_End{}, &buf) // end if worker_id==0

	// Per-worker initialization (always)
	// Compute worker_region_base = SCHED_PER_WORKER_START + worker_id * SCHED_WORKER_REGION_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // worker_id
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_WORKER_REGION_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // local 1 = worker_region_base

	// local queue head = 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// local queue tail = 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// local queue capacity = SCHED_LOCAL_QUEUE_CAP
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP)}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// local queue mask = SCHED_LOCAL_QUEUE_CAP - 1
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf)

	// LIFO slot = 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = SCHED_LOCAL_QUEUE_SIZE}, &buf)

	// tick_counter = 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(
		Wasm_I32_Store{align = 2, offset = SCHED_LOCAL_QUEUE_SIZE + SCHED_LIFO_SLOT_SIZE},
		&buf,
	)

	// budget_local = SCHED_BUDGET
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BUDGET)}, &buf)
	emit_instruction(
		Wasm_I32_Store{align = 2, offset = SCHED_LOCAL_QUEUE_SIZE + SCHED_LIFO_SLOT_SIZE + 4},
		&buf,
	)

	// current_task = 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = SCHED_CURRENT_TASK_OFFSET}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // worker_region_base

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_spawn_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
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
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
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
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Notify, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_complete_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SECTION)

	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	join_map_base :=
		handle_table_base + SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE

	// 1. Set handle entry to COMPLETED
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf) // entry_ptr

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_COMPLETED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf) // status = COMPLETED

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf) // result_tag

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf) // result_value

	// 2. Scan join_map for a waiter on this handle_id
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // next_free = count
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // join_map_count

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // block 1 (break after found)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop 0

	// if i >= join_map_count: break
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break out of block

	// Compute join_entry_ptr = join_map_base + 4 + i * JOIN_MAP_ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_JOIN_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Check if join_entry.handle_id == handle_id
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // entry handle_id
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // our handle_id
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Found a waiter! Get task_ptr from entry
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf) // task_ptr (closure)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf) // task_ptr (closure)

	// Remove join entry: swap with last and decrement count
	// Only if i != count - 1
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_I32_Ne{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Copy last entry to current slot
	// last_entry_addr = join_map_base + 4 + (count-1) * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_JOIN_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 9}, &buf) // last_entry_addr

	// Copy handle_id from last to current
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Copy task_ptr from last to current
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end swap-if

	// Decrement next_free
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Enqueue the waiter's task to worker 0's local queue
	// Extract fn_index and env_ptr from closure
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 10}, &buf) // fn_index

	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 11}, &buf) // env_ptr

	// Push to local queue tail
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // tail
	emit_instruction(Wasm_Local_Tee{index = 12}, &buf)

	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 12}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 13}, &buf) // q_entry_addr

	emit_instruction(Wasm_Local_Get{index = 13}, &buf)
	emit_instruction(Wasm_Local_Get{index = 10}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf) // fn_index

	emit_instruction(Wasm_Local_Get{index = 13}, &buf)
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf) // env_ptr

	emit_instruction(Wasm_Local_Get{index = 13}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf) // handle_id = 0

	emit_instruction(Wasm_Local_Get{index = 13}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf) // flags = 0

	// new_tail = (tail + 1) & (CAP - 1)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 12}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Break out of the search loop — we found our waiter
	emit_instruction(Wasm_Br{label = 1}, &buf) // break out of block

	emit_instruction(Wasm_End{}, &buf) // end if (found match)

	// i++
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf) // continue loop

	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	emit_instruction(Wasm_End{}, &buf) // end function

	locals := make([]Wasm_Local_Decl, 11)
	for i in 0 ..< 11 {
		locals[i] = Wasm_Local_Decl {
			count = 1,
			type  = .I32,
		}
	}

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_join_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	join_map_base :=
		handle_table_base + SCHED_HANDLE_TABLE_SIZE + SCHED_GLOBAL_QUEUE_SIZE + SCHED_WAIT_MAP_SIZE
	current_task_addr := SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET

	// Compute entry_ptr = handle_table_base + 4 + handle_id * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(handle_table_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // handle_id (param, local 0)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_HANDLE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // entry_ptr

	// Block for early exit with result
	emit_instruction(Wasm_Block{block_type = .I32}, &buf) // block 2: exit with i32 result
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop 1: recheck

	// Check COMPLETED: if status == COMPLETED, set JOINED, load result and branch out
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // status
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_COMPLETED}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Set status to JOINED
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_JOINED}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	// Load result_value and branch out
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf) // result_value
	emit_instruction(Wasm_Br{label = 2}, &buf) // branch out of block with result
	emit_instruction(Wasm_End{}, &buf)

	// Check CANCELLED: if status == CANCELLED, return 0
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // status
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_CANCELLED}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Br{label = 2}, &buf) // branch out of block with 0
	emit_instruction(Wasm_End{}, &buf)

	// PENDING: register in join_map, then re-enqueue current task and yield
	// Read join_map next_free count
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // next_free
	emit_instruction(Wasm_Local_Set{index = 2}, &buf) // join_map_count

	// Compute join_entry_addr = join_map_base + 4 + count * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_JOIN_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf) // join_entry_addr

	// Store handle_id at join_entry + 0
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // handle_id
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Store current_task closure at join_entry + 4
	emit_instruction(Wasm_I32_Const{value = i32(current_task_addr)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // current_task
	emit_instruction(Wasm_Local_Set{index = 4}, &buf) // current_task closure

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf) // task_ptr

	// Increment join_map next_free
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Re-enqueue current task to local queue (same as sched_yield)
	// Load current_task closure pointer
	emit_instruction(Wasm_I32_Const{value = i32(current_task_addr)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // current_task for yield

	// If current_task == 0, skip re-enqueue (shouldn't happen)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Br{label = 1}, &buf) // loop back to recheck
	emit_instruction(Wasm_End{}, &buf)

	// Extract fn_index from closure: closure + CAMP_TAG_FIELDS_OFFSET
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // fn_index

	// Extract env_ptr from closure: closure + CAMP_TAG_FIELDS_OFFSET + 8
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf) // env_ptr

	// Push to back of worker 0's local queue
	// tail = i32.load(SCHED_PER_WORKER_START + 4)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // tail
	emit_instruction(Wasm_Local_Tee{index = 8}, &buf) // tail

	// entry_addr = SCHED_PER_WORKER_START + 16 + tail * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 9}, &buf) // q_entry_addr

	// store fn_index at entry + 0
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// store env_ptr at entry + 4
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// store handle_id = 0 at entry + 8
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// store flags = 0 at entry + 12
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf)

	// new_tail = (tail + 1) & (CAP - 1)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Clear current_task to indicate task is parked
	emit_instruction(Wasm_I32_Const{value = i32(current_task_addr)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Return 0 (placeholder; task is parked and will be woken by sched_complete or re-run via yield)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Br{label = 2}, &buf) // exit with 0

	emit_instruction(Wasm_End{}, &buf) // end loop
	// After loop (unreachable): return 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end block
	emit_instruction(Wasm_End{}, &buf) // end function

	locals := make([]Wasm_Local_Decl, 10)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // entry_ptr
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // join_map_count
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // join_entry_addr
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // current_task (for join_map)
	locals[4] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // current_task (for yield)
	locals[5] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // fn_index
	locals[6] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // env_ptr
	locals[7] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // tail
	locals[8] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // q_entry_addr
	locals[9] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // spare

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_cancel_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)
	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
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
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Notify, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_yield_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	current_task_addr := SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET

	// Block for early exit when current_task == 0
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)

	// Load current_task closure pointer
	emit_instruction(Wasm_I32_Const{value = i32(current_task_addr)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 0}, &buf)

	// If current_task == 0, skip re-enqueue
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 0}, &buf)

	// Extract fn_index from closure: closure + CAMP_TAG_FIELDS_OFFSET
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// Extract env_ptr from closure: closure + CAMP_TAG_FIELDS_OFFSET + 8
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// Push to back of worker 0's local queue
	// tail is at worker_region_base + 4
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 3}, &buf)

	// entry_addr = worker_region_base + 16 + tail * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// store fn_index at entry + 0
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// store env_ptr at entry + 4
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// store handle_id = 0 at entry + 8
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// store flags = 0 at entry + 12
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf)

	// new_tail = (tail + 1) & (CAP - 1)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Clear current_task to indicate task is yielding
	emit_instruction(Wasm_I32_Const{value = i32(current_task_addr)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end block
	emit_instruction(Wasm_End{}, &buf) // end function

	locals := make([]Wasm_Local_Decl, 5)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // current_task
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // fn_index
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // env_ptr
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // tail
	locals[4] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // entry_addr

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_block_io_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MODERATE)

	wait_map_base :=
		SCHED_BASE +
		SCHED_WORKER_COUNT_SIZE +
		SCHED_SPINNING_SIZE +
		SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE +
		SCHED_GLOBAL_QUEUE_SIZE

	// Read current next_free count
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // next_free
	emit_instruction(Wasm_Local_Set{index = 2}, &buf) // local 2 = count

	// Compute entry address: wait_map_base + 4 + count * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_WAIT_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf) // entry_addr

	// Store pollable_handle
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // pollable_handle
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Store task_ptr (from parameter, which is now sched_current_task())
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // task_ptr
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// Increment next_free
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Clear current_task to park this task
	emit_instruction(
		Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET)},
		&buf,
	)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // count
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // entry_addr

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_timer_insert_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
	timer_wheel_base :=
		SCHED_BASE +
		SCHED_WORKER_COUNT_SIZE +
		SCHED_SPINNING_SIZE +
		SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE +
		SCHED_GLOBAL_QUEUE_SIZE +
		SCHED_WAIT_MAP_SIZE +
		SCHED_JOIN_MAP_SIZE
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
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	}
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[4] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[5] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[6] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_timer_cancel_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)
	timer_wheel_base :=
		SCHED_BASE +
		SCHED_WORKER_COUNT_SIZE +
		SCHED_SPINNING_SIZE +
		SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE +
		SCHED_GLOBAL_QUEUE_SIZE +
		SCHED_WAIT_MAP_SIZE +
		SCHED_JOIN_MAP_SIZE
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
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_notify_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Notify, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_park_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)
	notification_base := SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(notification_base)}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Wait32, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_worker_loop_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XL)
	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	global_queue_base := handle_table_base + SCHED_HANDLE_TABLE_SIZE
	timer_wheel_base :=
		SCHED_BASE +
		SCHED_WORKER_COUNT_SIZE +
		SCHED_SPINNING_SIZE +
		SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE +
		SCHED_GLOBAL_QUEUE_SIZE +
		SCHED_WAIT_MAP_SIZE +
		SCHED_JOIN_MAP_SIZE
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
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
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Wait32, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)
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
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 8)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[4] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[5] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[6] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[7] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_parallel_map_body :: proc(runtime_indices: [RUNTIME_FUNC_COUNT]int) -> Wasm_Code {
	// camp_parallel_map(fn_idx: i32, fn_env: i32, items_ptr: i32, items_len: i32, chunk_size: i32) -> i32
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
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
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
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
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_current_task_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_TINY)
	emit_instruction(
		Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET)},
		&buf,
	)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_run_single_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XL)

	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
	global_queue_base := handle_table_base + SCHED_HANDLE_TABLE_SIZE
	wait_map_base := global_queue_base + SCHED_GLOBAL_QUEUE_SIZE
	join_map_base := wait_map_base + SCHED_WAIT_MAP_SIZE
	timer_wheel_base :=
		SCHED_BASE +
		SCHED_WORKER_COUNT_SIZE +
		SCHED_SPINNING_SIZE +
		SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE +
		SCHED_GLOBAL_QUEUE_SIZE +
		SCHED_WAIT_MAP_SIZE +
		SCHED_JOIN_MAP_SIZE
	timer_pool_base := timer_wheel_base + SCHED_TIMER_WHEEL_SIZE

	// Locals: 0=head, 1=tail, 2=entry_addr, 3=fn_index, 4=env_ptr,
	//         5=budget_remaining, 6=global_head, 7=global_tail,
	//         8=wait_map_count, 9=timer_pool_count, 10=join_map_count,
	//         11=scratch, 12=pool_idx

	// Initialize budget
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BUDGET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // budget_remaining

	// block 1 = exit point, loop 0 = continue point
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// ---- 1. Try local queue ----
	// head = i32.load(SCHED_PER_WORKER_START + 0)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 0}, &buf) // head

	// tail = i32.load(SCHED_PER_WORKER_START + 4)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // tail

	// if head != tail: dequeue
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Ne{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// entry_addr = SCHED_PER_WORKER_START + 16 + head * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// fn_index = i32.load(entry_addr + 0)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// env_ptr = i32.load(entry_addr + 4)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Advance head: new_head = (head + 1) & (CAP - 1)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Set current_task = env_ptr
	emit_instruction(
		Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET)},
		&buf,
	)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Run task: call_indirect(env_ptr, fn_index)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf) // env_ptr (first arg)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf) // fn_index (table index)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)

	// Clear current_task
	emit_instruction(
		Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET)},
		&buf,
	)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Budget: budget_remaining -= 1
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 5}, &buf)
	// if budget_remaining <= 0: process timers, reset budget
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Le_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Update timer_wheel current_time via clock_time_get
	emit_instruction(Wasm_I32_Const{value = 1}, &buf) // CLOCK_MONOTONIC
	emit_instruction(Wasm_I64_Const{value = 0}, &buf) // precision
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf) // out_ptr
	emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_CLOCK_TIME_GET)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// Process level-0 timer slots: walk linked lists for expired entries
	// For each of 64 level-0 slots, check if slot_head != 0
	// If so, walk the linked list from timer_pool and re-enqueue expired tasks
	// This is inline timer processing for single-threaded mode
	// slot_heads start at timer_wheel_base + 8
	// We process slot 0 only as a simplification (full processing in timer_tick body)
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base + 8)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // slot_head[0]
	emit_instruction(Wasm_Local_Set{index = 12}, &buf) // pool_idx

	// If pool_idx != 0, walk the timer chain
	emit_instruction(Wasm_Local_Get{index = 12}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // pool_idx != 0
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Inner loop: walk timer chain for slot 0
	// pool_entry_addr = timer_pool_base + 4 + pool_idx * SCHED_TIMER_ENTRY_SIZE
	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // block: exit walk
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop: continue walk

	// Compute entry address
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 12}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_TIMER_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 11}, &buf) // scratch = entry_addr

	// Load expiry (i64) from entry
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, &buf)

	// Load current_time from timer_wheel
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, &buf)

	// If expiry > current_time: not expired yet, break walk
	emit_instruction(Wasm_I64_Le_S{}, &buf) // expiry <= current_time
	emit_instruction(Wasm_I32_Eqz{}, &buf) // expiry > current_time
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break out of walk

	// Task is expired: load task_ptr and next from pool entry
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf) // task_ptr
	emit_instruction(Wasm_Local_Set{index = 2}, &buf) // reuse entry_addr as task_ptr

	// Load fn_index and env_ptr from the task closure
	// Task closure layout: fn_index(4) + env_ptr(4) at task_ptr
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // fn_index
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf) // env_ptr
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Enqueue task to local queue tail
	// tail = i32.load(SCHED_PER_WORKER_START + 4)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 11}, &buf) // scratch = tail

	// store fn_index at entries[tail]
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// store env_ptr at entries[tail] + 4
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// Advance tail: new_tail = (tail + 1) & (CAP - 1)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Move to next in chain: next = i32.load(entry_addr + 12)
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	// Re-compute entry addr for this pool_idx
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 12}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_TIMER_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 12}, &buf) // next
	emit_instruction(Wasm_Local_Set{index = 12}, &buf)

	// Update slot_head to next (unlink expired entry)
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base + 8)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 12}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// If next != 0, continue walking
	emit_instruction(Wasm_Local_Get{index = 12}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // next != 0
	emit_instruction(Wasm_Br_If{label = 0}, &buf) // continue walk loop

	emit_instruction(Wasm_End{}, &buf) // end walk loop
	emit_instruction(Wasm_End{}, &buf) // end walk block

	emit_instruction(Wasm_End{}, &buf) // end if pool_idx != 0

	// Reset budget
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BUDGET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if budget exhausted

	// Continue main loop
	emit_instruction(Wasm_Br{label = 0}, &buf) // back to loop

	emit_instruction(Wasm_End{}, &buf) // end if (local queue has work)

	// ---- 2. Try global queue ----
	// global_head = i32.load(global_queue_base)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// global_tail = i32.load(global_queue_base + 4)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf)

	// if global_head != global_tail: dequeue
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Ne{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// entry_addr = global_queue_base + 12 + global_head * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base + 12)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// fn_index = i32.load(entry_addr + 0)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// env_ptr = i32.load(entry_addr + 4)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// Advance global head (single-threaded, no atomics)
	emit_instruction(Wasm_I32_Const{value = i32(global_queue_base)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Set current_task = env_ptr
	emit_instruction(
		Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET)},
		&buf,
	)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Run task: call_indirect(env_ptr, fn_index)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Call_Indirect{type_idx = 0, table_idx = 0}, &buf)

	// Clear current_task
	emit_instruction(
		Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + SCHED_CURRENT_TASK_OFFSET)},
		&buf,
	)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Continue loop
	emit_instruction(Wasm_Br{label = 0}, &buf) // back to loop

	emit_instruction(Wasm_End{}, &buf) // end if (global queue has work)

	// ---- 3. No ready work: check for blocked tasks / timers ----
	// wait_map_count = i32.load(wait_map_base) -- next_free counter
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf)

	// timer_pool_count = i32.load(timer_pool_base) -- next_free counter
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 9}, &buf)

	// if (wait_map_count > 0 || timer_pool_count > 0): yield to WASI then loop
	// Compute: NOT (wait_map_count == 0 AND timer_pool_count == 0)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // wait_map_count == 0
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // timer_pool_count == 0
	emit_instruction(Wasm_I32_And{}, &buf) // both zero
	emit_instruction(Wasm_I32_Eqz{}, &buf) // NOT both zero = has blocked work
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Yield to WASI runtime to allow I/O processing
	emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_SCHED_YIELD)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// After yielding, loop back to check for work
	emit_instruction(Wasm_Br{label = 0}, &buf) // back to loop

	emit_instruction(Wasm_End{}, &buf) // end if has blocked work

	// ---- 4. Check exit condition ----
	// Also need join_map_count
	emit_instruction(Wasm_I32_Const{value = i32(join_map_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 10}, &buf) // join_map_count

	// If wait_map_count == 0 AND timer_pool_count == 0 AND join_map_count == 0: exit
	// (wait_map_count | timer_pool_count | join_map_count) == 0 means no work anywhere
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Or{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 10}, &buf)
	emit_instruction(Wasm_I32_Or{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // all zero?
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break to exit

	// ---- 5. Fallback: yield to WASI and loop ----
	emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_SCHED_YIELD)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf) // back to loop

	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block
	emit_instruction(Wasm_End{}, &buf) // end function

	locals := make([]Wasm_Local_Decl, 13)
	for i in 0 ..< 13 {
		locals[i] = Wasm_Local_Decl {
			count = 1,
			type  = .I32,
		}
	}

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}


emit_camp_sched_poll_and_dispatch_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XL)

	wait_map_base :=
		SCHED_BASE +
		SCHED_WORKER_COUNT_SIZE +
		SCHED_SPINNING_SIZE +
		SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE +
		SCHED_GLOBAL_QUEUE_SIZE

	scratch_base := SCHED_PER_WORKER_START + SCHED_WORKER_REGION_SIZE

	// Read wait_map count (next_free at wait_map_base + 0)
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 0}, &buf) // local 0 = wait_map_count

	// If count == 0: nothing to poll, return
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_End{}, &buf) // early return

	// Build subscription array at scratch_base
	// For each wait_map entry i: write 48-byte subscription
	// userdata(8) = i, type(1) = 0 (fd_read), fd(4) = entry.pollable_handle
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // local 1 = i

	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // block @1
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop @0

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break if i >= count

	// wait_entry_addr = wait_map_base + 4 + i * SCHED_WAIT_MAP_ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_WAIT_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf) // local 2 = wait_entry_addr

	// Read pollable_handle (fd) from entry + 0
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf) // local 3 = pollable_handle (fd)

	// sub_addr = scratch_base + i * 48
	emit_instruction(Wasm_I32_Const{value = i32(scratch_base)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 48}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf) // local 4 = sub_addr

	// Write userdata = i (as u64 low bits)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = 0}, &buf)

	// Write type = 0 (fd_read) at sub_addr + 8
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = 8}, &buf)

	// Write fd = pollable_handle at sub_addr + 16
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 16}, &buf)

	// i++
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf) // continue loop

	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// Call poll_oneoff(scratch_base, result_base, nsubs, nsubs)
	// Result buffer at scratch_base + 2048
	emit_instruction(Wasm_I32_Const{value = i32(scratch_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(scratch_base + 2048)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // nsubs
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // nevents (same as nsubs)
	emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_POLL_ONEOFF)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf) // drop errno

	// Process results: for each event, check if fd is ready and enqueue task
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // i = 0

	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // block @3
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop @2

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break if i >= nsubs

	// result_addr = scratch_base + 2048 + i * 24
	emit_instruction(Wasm_I32_Const{value = i32(scratch_base + 2048)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 24}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // local 5 = result_addr

	// Read errno low byte at result_addr + 8; if 0, fd is ready
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = 8}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // errno == 0 → ready
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Read userdata (entry index) from result_addr + 0
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // local 6 = entry_index

	// Look up wait_map entry: wait_map_base + 4 + entry_index * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_WAIT_MAP_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf) // reuse local 2 = wait_entry_addr

	// Read task_ptr from entry + 4
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 4}, &buf)
	emit_instruction(Wasm_Local_Set{index = 7}, &buf) // local 7 = task_ptr (closure)

	// If task_ptr != 0, enqueue to local queue
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 0}, &buf) // skip if null (targets the if)

	// Extract fn_index from closure
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 8}, &buf) // local 8 = fn_index

	// Extract env_ptr from closure
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 9}, &buf) // local 9 = env_ptr

	// Push to local queue (same pattern as yield)
	// Read tail at SCHED_PER_WORKER_START + 4
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 10}, &buf) // local 10 = tail

	// entry_addr = SCHED_PER_WORKER_START + 16 + tail * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 10}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 11}, &buf) // local 11 = q_entry_addr

	// Store fn_index at entry + 0
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_Local_Get{index = 8}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Store env_ptr at entry + 4
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_Local_Get{index = 9}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf)

	// Store handle_id = 0 at entry + 8
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	// Store flags = 0 at entry + 12
	emit_instruction(Wasm_Local_Get{index = 11}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf)

	// Advance tail: (tail + 1) & (CAP - 1)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 10}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if task_ptr != 0

	// Clear the wait_map entry (mark as consumed)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf) // clear pollable_handle
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf) // clear task_ptr

	emit_instruction(Wasm_End{}, &buf) // end if ready

	// i++
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf) // continue loop

	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	emit_instruction(Wasm_End{}, &buf) // end function

	locals := make([]Wasm_Local_Decl, 12)
	for i in 0 ..< 12 {
		locals[i] = Wasm_Local_Decl {
			count = 1,
			type  = .I32,
		}
	}

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}
emit_camp_sched_timer_tick_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XL)

	join_map_base :=
		SCHED_BASE +
		SCHED_WORKER_COUNT_SIZE +
		SCHED_SPINNING_SIZE +
		SCHED_NOTIFICATION_SIZE +
		SCHED_HANDLE_TABLE_SIZE +
		SCHED_GLOBAL_QUEUE_SIZE +
		SCHED_WAIT_MAP_SIZE
	timer_wheel_base := join_map_base + SCHED_JOIN_MAP_SIZE
	timer_pool_base := timer_wheel_base + SCHED_TIMER_WHEEL_SIZE

	// 1. Update current_time via clock_time_get
	emit_instruction(Wasm_I32_Const{value = 1}, &buf) // CLOCK_MONOTONIC
	emit_instruction(Wasm_I64_Const{value = 0}, &buf) // precision
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf) // out_ptr
	emit_instruction(Wasm_Call{index = u32(WASI_IMPORT_CLOCK_TIME_GET)}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)

	// 2. Process level 0 expired timers
	// Locals: 0=slot_idx, 1=pool_idx, 2=pool_entry_addr, 3=task_ptr,
	//         4=fn_index, 5=env_ptr, 6=q_entry_addr, 7=tail, 8=next_pool_idx

	// slot_idx = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 0}, &buf)

	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // block 1: exit
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop 0: continue

	// if slot_idx >= 64: break
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 64}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Read slot_head = i32.load(timer_wheel_base + 8 + slot_idx * 4)
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base + 8)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // pool_idx

	// If pool_idx == 0: skip (empty slot)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 0}, &buf) // continue to next slot

	// Walk linked list at this slot
	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // block 3: done with slot
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // loop 2: walk list

	// pool_entry_addr = timer_pool_base + 4 + pool_idx * ENTRY_SIZE
	emit_instruction(Wasm_I32_Const{value = i32(timer_pool_base + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_TIMER_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// Check task_ptr != 0 (not cancelled)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf) // task_ptr
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Cancelled: skip to next
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 12}, &buf) // next
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // end of list
	emit_instruction(Wasm_Br{label = 1}, &buf) // continue walking
	emit_instruction(Wasm_End{}, &buf)

	// Compare expiry <= current_time
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, &buf) // expiry
	emit_instruction(Wasm_I32_Const{value = i32(timer_wheel_base)}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = 0}, &buf) // current_time
	emit_instruction(Wasm_I64_Le_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Timer expired! Get task_ptr
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf) // task_ptr

	// Extract fn_index from closure
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf) // fn_index

	// Extract env_ptr from closure
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // env_ptr

	// Push to local queue
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf) // tail
	emit_instruction(Wasm_Local_Tee{index = 7}, &buf)

	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 16)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_ENTRY_SIZE)}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // q_entry_addr

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf) // fn_index

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 4}, &buf) // env_ptr

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf)

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 12}, &buf)

	// Advance tail: (tail + 1) & (CAP - 1)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_PER_WORKER_START + 4)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_LOCAL_QUEUE_CAP - 1)}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// Mark pool entry as consumed
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 8}, &buf) // task_ptr = 0

	emit_instruction(Wasm_End{}, &buf) // end if expired

	// Move to next entry
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 12}, &buf) // next
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 0}, &buf) // end of list
	emit_instruction(Wasm_Br{label = 1}, &buf) // continue walking

	emit_instruction(Wasm_End{}, &buf) // end loop 2
	emit_instruction(Wasm_End{}, &buf) // end block 3

	// slot_idx++
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 0}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf) // continue outer loop

	emit_instruction(Wasm_End{}, &buf) // end loop 0
	emit_instruction(Wasm_End{}, &buf) // end block 1
	emit_instruction(Wasm_End{}, &buf) // end function

	locals := make([]Wasm_Local_Decl, 9)
	for i in 0 ..< 9 {
		locals[i] = Wasm_Local_Decl {
			count = 1,
			type  = .I32,
		}
	}

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_sched_timer_process_expired_body :: proc() -> Wasm_Code {
	// Timer processing is inlined in timer_tick for single-threaded mode.
	// This function exists as a separate entry point for explicit invocation.
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_TINY)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_i64_to_str_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	// camp_i64_to_str(val: i64) -> i32 (Str pointer)
	// String layout: [len: i32][data: bytes...]
	// Locals: 1=abs_val(i64), 2=is_neg(i32), 3=num_digits(i32), 4=total_len(i32), 5=result(i32), 6=pos(i32)
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_LARGE)

	// Check if negative
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // val
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_I64_Lt_S{}, &buf) // val < 0
	emit_instruction(Wasm_Local_Set{index = 2}, &buf) // is_neg = val < 0

	// abs_val = is_neg ? -val : val
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_If{block_type = .I64}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf) // -val
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // val
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // abs_val

	// Count digits: num_digits = 1, temp = abs_val
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf) // num_digits = 1

	// while temp >= 10: temp /= 10, num_digits++
	// while temp >= 10: temp /= 10, num_digits++
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Lt_S{}, &buf) // abs_val < 10
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break if abs_val < 10
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Div_S{}, &buf) // abs_val / 10
	emit_instruction(Wasm_Local_Set{index = 1}, &buf) // abs_val = abs_val / 10
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // num_digits + 1
	emit_instruction(Wasm_Local_Set{index = 3}, &buf) // num_digits++
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Recompute abs_val (counting loop destroyed it)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_If{block_type = .I64}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// total_len = num_digits + (is_neg ? 1 : 0)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf) // is_neg (0 or 1)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf) // total_len

	// result = alloc(total_len + 4)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf) // result

	// [result] = total_len
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// pos = total_len - 1 (write digits right-to-left)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf) // pos

	// Write digits from right to left
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	// Store digit = abs_val % 10 + '0'
	emit_instruction(Wasm_Local_Get{index = 5}, &buf) // result
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // data_ptr = result + 4
	emit_instruction(Wasm_Local_Get{index = 6}, &buf) // pos
	emit_instruction(Wasm_I32_Add{}, &buf) // data_ptr + pos
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // abs_val
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Rem_S{}, &buf) // abs_val % 10
	emit_instruction(Wasm_I32_Wrap_I64{}, &buf) // as i32
	emit_instruction(Wasm_I32_Const{value = 48}, &buf) // '0'
	emit_instruction(Wasm_I32_Add{}, &buf) // digit + '0'
	emit_instruction(Wasm_I32_Store8{align = 0, offset = 0}, &buf) // store byte

	// abs_val /= 10
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Div_S{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// pos--
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 6}, &buf)

	// if pos < 0: break
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Write '-' sign if negative
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf) // result
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf) // result + 4
	emit_instruction(Wasm_I32_Const{value = 45}, &buf) // '-'
	emit_instruction(Wasm_I32_Store8{align = 0, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 5}, &buf) // return result
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 5)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	} // abs_val
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // is_neg
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // num_digits
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // total_len
	locals[4] = Wasm_Local_Decl {
		count = 2,
		type  = .I32,
	} // result, pos

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_i32_to_str_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	// camp_i32_to_str(val: i32) -> i32 (Str pointer)
	// Sign-extend to i64 and inline the conversion (simpler than calling i64 version)
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_LARGE)

	// Sign-extend to i64 and use as abs_val (local 1)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// is_neg = abs_val < 0 (local 2)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_I64_Lt_S{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// abs_val = is_neg ? -val : val
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_If{block_type = .I64}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// Count digits
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Div_S{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Recompute abs_val
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_I64_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .I64}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// total_len
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// result = alloc(total_len + 4)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// [result] = total_len
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	// pos = total_len - 1
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Write digits
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Rem_S{}, &buf)
	emit_instruction(Wasm_I32_Wrap_I64{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 48}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 10}, &buf)
	emit_instruction(Wasm_I64_Div_S{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)
	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Write '-' if negative
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 45}, &buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 5)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[3] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[4] = Wasm_Local_Decl {
		count = 2,
		type  = .I32,
	}

	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_f64_to_str_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	// Stub: returns "0.0"
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_camp_bool_to_str_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	// Stub: returns null
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

