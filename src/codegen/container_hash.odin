package codegen

// emit_result_eq_body generates runtime body for Result.eq.
// Signature: (ok_eq_fn: i32, err_eq_fn: i32, a: i32, b: i32) -> i32
// Returns 1 if equal, 0 otherwise.
emit_result_eq_body :: proc(compare_type_idx: int, table_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// Load tag bytes
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// If tags differ: return 0
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Ne{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// If tag == 0 (Ok): compare Ok payloads using ok_eq_fn
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Both Ok
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // ok_eq_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Both Err: compare Err payloads using err_eq_fn
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // err_eq_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 3,
		type  = .I32,
	} // locals 4-6
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// emit_result_compare_body generates runtime body for Result.compare.
// Signature: (ok_cmp_fn: i32, err_cmp_fn: i32, a: i32, b: i32) -> i32
// Returns -1 (Less), 0 (Equal), or 1 (Greater).
emit_result_compare_body :: proc(compare_type_idx: int, table_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// Load tag bytes
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// If both same tag, compare payloads
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Eq{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Same tag: check which tag
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Both Ok: compare Ok payloads
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // ok_cmp_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	// Both Err: compare Err payloads
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // err_cmp_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Different tags: Ok (0) < Err (1)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// tag_a < tag_b: a is Ok, b is Err -> Ok < Err
	emit_instruction(Wasm_I32_Const{value = -1}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	// tag_a > tag_b: a is Err, b is Ok -> Err > Ok
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 2,
		type  = .I32,
	} // locals 4-5
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// emit_result_hash_body generates runtime body for Result.hash.
// Signature: (ok_hash_fn: i32, err_hash_fn: i32, result: i32, hasher: i32) -> i32
emit_result_hash_body :: proc(compare_type_idx: int, table_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// Load tag
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// If Ok (tag==0): hash payload with ok_hash_fn
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf) // hasher
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // ok_hash_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Err: hash payload with err_hash_fn
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf) // hasher
	emit_instruction(Wasm_Local_Get{index = 1}, &buf) // err_hash_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // local 4
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// emit_list_compare_body generates runtime body for List.compare.
// Signature: (cmp_fn: i32, a: i32, b: i32) -> i32
// Walks two Nil/Cons lists in lockstep. Returns -1, 0, or 1.
emit_list_compare_body :: proc(compare_type_idx: int, table_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// block $break, loop $walk
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if current_a == 0, break
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load tag of current_a
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// Load tag of current_b
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// If current_a is Nil (tag==0)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// current_a is Nil
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// Both Nil: break (all equal so far, we'll return 0)
	emit_instruction(Wasm_Br{label = 1}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	// a is Nil, b is Cons: a is shorter -> return -1
	emit_instruction(Wasm_I32_Const{value = -1}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// current_a is Cons (tag != 0)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// a is Cons, b is Nil: b is shorter -> return 1
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Both Cons: compare head elements
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // cmp_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// If cmp_fn returned non-zero, return result
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // double eqz = not zero
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Advance to tails (Cons field[1] at CAMP_TAG_FIELDS_OFFSET + 8)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf) // continue loop
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// Both lists fully walked with all equal: return 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 3,
		type  = .I32,
	} // locals 3-5
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// emit_list_hash_body generates runtime body for List.hash.
// Signature: (hash_fn: i32, list: i32, hasher: i32) -> i32
// Walks the Nil/Cons list, hashing each element.
emit_list_hash_body :: proc(compare_type_idx: int, table_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// block $break, loop $walk
	emit_instruction(Wasm_Block{block_type = .Void}, &buf)
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf)

	// if current == 0, break
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Load tag byte
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// if tag == 0 (Nil), break
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// Hash the head element: hash_fn(head, hasher) -> new_hasher
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf) // hasher
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // hash_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf) // update hasher

	// Advance to tail (Cons field[1] at CAMP_TAG_FIELDS_OFFSET + 8)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf) // continue loop
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// Return hasher
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // local 3
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

