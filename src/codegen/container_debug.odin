package codegen

// emit_list_debug_body emits the runtime body for List.debug.
// Signature: (elem_debug_fn: i32, list: i32) -> i32
emit_list_debug_body :: proc(
	str_concat_func_idx: int,
	debug_cb_type_idx: int,
	table_idx: int,
	open_offset: u32,
	close_offset: u32,
	sep_offset: u32,
) -> Wasm_Code {
	// Params: 0=elem_debug_fn, 1=list_ptr
	// Locals: 2=result(Str), 3=current(Cons ptr), 4=is_first(i32), 5=elem_str(Str)
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// result = "["
	emit_instruction(Wasm_I32_Const{value = i32(open_offset)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// current = list_ptr
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// is_first = 1
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// block $break, loop $walk
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if current == 0, break
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load tag byte at CAMP_TAG_TAG_OFFSET (4)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)

	// if tag == 0 (Nil), break
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// If not first element, prepend ", "
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(sep_offset)}, &buf)
	emit_instruction(Wasm_Call{index = u32(str_concat_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// is_first = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// elem = current.field[0], call debug_fn, concat
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(debug_cb_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Call{index = u32(str_concat_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// current = tail
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 4)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// return Str_Concat(result, "]")
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(close_offset)}, &buf)
	emit_instruction(Wasm_Call{index = u32(str_concat_func_idx)}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl {
		count = 3,
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

// emit_result_debug_body emits the runtime body for Result.debug.
// Signature: (ok_debug_fn: i32, err_debug_fn: i32, result: i32) -> i32
emit_result_debug_body :: proc(
	str_concat_func_idx: int,
	debug_cb_type_idx: int,
	table_idx: int,
	ok_prefix_offset: u32,
	err_prefix_offset: u32,
	close_offset: u32,
) -> Wasm_Code {
	// Params: 0=ok_debug_fn, 1=err_debug_fn, 2=result_ptr
	// Locals: 3=tag, 4=val_str, 5=temp
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_LARGE)

	// Load tag
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// if tag == 0 (Ok)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Ok: load payload, call ok_debug_fn
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(debug_cb_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// temp = Str_Concat("Ok(", val_str)
	emit_instruction(Wasm_I32_Const{value = i32(ok_prefix_offset)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Call{index = u32(str_concat_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_Else{}, &buf)

	// Err: load payload, call err_debug_fn
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(debug_cb_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// temp = Str_Concat("Err(", val_str)
	emit_instruction(Wasm_I32_Const{value = i32(err_prefix_offset)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Call{index = u32(str_concat_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if

	// return Str_Concat(temp, ")")
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = i32(close_offset)}, &buf)
	emit_instruction(Wasm_Call{index = u32(str_concat_func_idx)}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl {
		count = 2,
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

