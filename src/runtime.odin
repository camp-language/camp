package camp

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

CAMP_LIST_HEADER_SIZE :: 20
CAMP_LIST_REFCOUNT_OFFSET :: 0
CAMP_LIST_TAG_OFFSET :: 4
CAMP_LIST_DATA_PTR_OFFSET :: 8
CAMP_LIST_LENGTH_OFFSET :: 12
CAMP_LIST_CAPACITY_OFFSET :: 16
CAMP_LIST_TYPE_MARKER :: 0xFD

emit_camp_list_alloc_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	emit_instruction(Wasm_I32_Const{value = CAMP_LIST_HEADER_SIZE}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_REFCOUNT_OFFSET}, &buf)

	emit_instruction(Wasm_I32_Const{value = CAMP_LIST_TYPE_MARKER}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_TAG_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_DATA_PTR_OFFSET}, &buf)

	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_LENGTH_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_CAPACITY_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
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

emit_camp_list_push_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 512)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_LIST_LENGTH_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_LIST_CAPACITY_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .I32}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_LIST_DATA_PTR_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_CAPACITY_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_DATA_PTR_OFFSET}, &buf)

	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_LIST_DATA_PTR_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_LIST_LENGTH_OFFSET}, &buf)

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

emit_camp_list_len_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 32)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_LIST_LENGTH_OFFSET}, &buf)
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
	buf = make([dynamic]u8, 0, 64)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_LIST_LENGTH_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Unreachable{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = CAMP_LIST_DATA_PTR_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Mul{}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
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

emit_camp_print_str_stderr_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
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

emit_camp_drop_reuse_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 128)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Sub{}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .I32}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Else{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)
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
