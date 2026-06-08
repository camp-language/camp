package codegen

emit_map_eq_body :: proc(compare_type_idx: int, table_idx: int) -> Wasm_Code {
	// (eq_fn: i32, cmp_fn: i32, map_a: i32, map_b: i32) -> i32
	// Structural equality for maps. Walks both sorted linked lists in lockstep.
	// Returns 1 if equal, 0 otherwise.
	// Locals: 0=eq_fn, 1=cmp_fn, 2=map_a, 3=map_b, 4=current_a, 5=current_b, 6=temp, 7=size_a
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// Check sizes match first
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_SIZE_FIELD_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 7}, &buf) // size_a
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_SIZE_FIELD_OFFSET}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Sizes differ: return 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end if

	// if size_a == 0, both empty: return 1
	emit_instruction(Wasm_Local_Get{index = 7}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end if

	// current_a = map_a.root, current_b = map_b.root
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_ROOT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_ROOT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// block $break, loop $walk
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if current_a == 0, break (both should be null at this point)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf) // break

	// Compare keys: cmp_fn(current_a.key, current_b.key)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_KEY_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_KEY_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // cmp_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// if cmp_result != 0: keys differ, return 0
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // double eqz = not zero
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end if

	// Compare values: eq_fn(current_a.value, current_b.value)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_VALUE_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_VALUE_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // eq_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// if eq_result == 0 (not equal): return 0
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end if

	// Advance both: current_a = current_a.next, current_b = current_b.next
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_NEXT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_NEXT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf) // continue loop
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// All elements matched: return 1
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 4,
		type  = .I32,
	} // locals 4-7: current_a, current_b, temp, size_a
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

emit_set_eq_body :: proc(compare_type_idx: int, table_idx: int) -> Wasm_Code {
	// (cmp_fn: i32, set_a: i32, set_b: i32) -> i32
	// Structural equality for sets. Walks both sorted linked lists in lockstep.
	// Returns 1 if equal, 0 otherwise.
	// Locals: 0=cmp_fn, 1=set_a, 2=set_b, 3=current_a, 4=current_b, 5=temp, 6=size_a
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XL)

	// Check sizes match first
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_SIZE_FIELD_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Tee{index = 6}, &buf) // size_a
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_SIZE_FIELD_OFFSET}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// if size_a == 0, both empty: return 1
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// current_a = set_a.root, current_b = set_b.root
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_ROOT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_HEADER_ROOT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// block $break, loop $walk
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if current_a == 0, break
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Compare keys: cmp_fn(current_a.key, current_b.key)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_KEY_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_KEY_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // cmp_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// if cmp_result != 0: keys differ, return 0
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Advance both
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_NEXT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = MAP_NODE_NEXT_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// All elements matched: return 1
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 4,
		type  = .I32,
	} // locals 3-6: current_a, current_b, temp, size_a
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

