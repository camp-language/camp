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
SCHED_WORKER_REGION_SIZE :: SCHED_LOCAL_QUEUE_SIZE + SCHED_LIFO_SLOT_SIZE + 4 + 4 // queue + lifo + tick_counter + budget_local

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

emit_camp_async_init_body :: proc() -> Wasm_Code {
	// Initialize async scheduler — no-op for now (scheduler state in linear memory)
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
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

emit_camp_async_enqueue_body :: proc() -> Wasm_Code {
	// camp_async_enqueue(closure_fn: i32, closure_env: i32) -> i32 (handle_id)
	// Simplified: return closure_fn as handle_id
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_TINY)
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

emit_camp_async_dequeue_body :: proc() -> Wasm_Code {
	// camp_async_dequeue() -> i32 (closure_fn, 0 = empty)
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
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

emit_camp_async_run_body :: proc() -> Wasm_Code {
	// camp_async_run() -> i32 (exit code)
	// Simplified: return 0
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SMALL)
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
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
	emit_instruction(Wasm_I32_Const{value = i32(SCHED_BASE)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(
		Wasm_I32_Const {
			value = i32(
				SCHED_BASE +
				SCHED_WORKER_COUNT_SIZE +
				SCHED_SPINNING_SIZE +
				SCHED_NOTIFICATION_SIZE,
			),
		},
		&buf,
	)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
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
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
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

emit_camp_sched_join_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)
	handle_table_base :=
		SCHED_BASE + SCHED_WORKER_COUNT_SIZE + SCHED_SPINNING_SIZE + SCHED_NOTIFICATION_SIZE
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
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = HANDLE_STATUS_COMPLETED}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 8}, &buf)
	emit_instruction(Wasm_Br{label = 2}, &buf) // branch out of block i32 with result
	emit_instruction(Wasm_End{}, &buf)
	// Check CANCELLED: if status == CANCELLED, return 0 and branch out
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
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
	emit_instruction(Wasm_Atomic_Mem{op = .Load, width = .I32, align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = -1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .Wait32, width = .I32, align = 2, offset = 0}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
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
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)
	emit_instruction(Wasm_End{}, &buf)
	locals := make([]Wasm_Local_Decl, 0)
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
	emit_instruction(Wasm_I32_Const{value = i32(wait_map_base)}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Atomic_Mem{op = .RMW_Add, width = .I32, align = 2, offset = 0}, &buf)
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
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
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

emit_camp_i64_to_str_body :: proc() -> Wasm_Code {
	// camp_i64_to_str(val: i64) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
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

emit_camp_i32_to_str_body :: proc() -> Wasm_Code {
	// camp_i32_to_str(val: i32) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
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

emit_camp_f64_to_str_body :: proc() -> Wasm_Code {
	// camp_f64_to_str(val: f64) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
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

emit_camp_bool_to_str_body :: proc() -> Wasm_Code {
	// camp_bool_to_str(val: i32) -> i32 (Str pointer)
	// Stub: returns null — real implementation later
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

