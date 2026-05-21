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

RUNTIME_THROW_HANDLER :: 5
RUNTIME_FUNC_COUNT_NEW :: 6

emit_camp_throw_handler_body :: proc(exit_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, 256)

	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4100}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = 4}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4096}, &buf)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_Call{index = 1}, &buf)
	emit_instruction(Wasm_Drop{}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Call{index = u32(exit_idx)}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 0)

	body := make([]u8, len(buf))
	for b, i in buf {
		body[i] = b
	}
	delete(buf)

	return Wasm_Code{locals = locals, body = body}
}
