package codegen

// Design B container compare ABI helpers.
//
// Under Design B, an element `Ord.compare` callback (typed `(i32, i32) -> i32`
// for `call_indirect`) returns an `Order` heap tag cell (a pointer to a
// CAMP_TAG_HEADER_SIZE cell whose tag byte is 0=Less, 1=Equal, 2=Greater),
// NOT a raw -1/0/1 i32. The container compare runtimes therefore must:
//   1. read the tag byte from the callback result,
//   2. map it to a trinary (-1/0/1) to drive their existing `<0`/`==0`/`>0`
//      branching, AND
//   3. Drop the intermediate `Order` cell (it has refcount 1) via camp_drop
//      (Runtime_Func.Drop, signature `(ptr: i32, depth: i32)` — depth=0)
//      once they no longer need the cell, to avoid leaking it.
//
// `I64_compare` itself stays the internal `(i64,i64)->i32` raw -1/0/1
// intrinsic; its `I64_Trampoline` adapter now wraps that result into an Order
// cell so every container element compare callback uniformly yields Order.

// consume_order_to_trinary is the canonical "read Order callback result and
// free it" sequence. On entry the Order cell pointer is on top of the stack.
// On exit the trinary (-1/0/1 = Less/Equal/Greater) is stored in
// `cmp_result_local`, the Order cell has been dropped via camp_drop
// (depth 0), and the stack is empty. `order_ptr_local` is scratch to hold
// the cell pointer across the tag load + drop.
consume_order_to_trinary :: proc(
	cmp_result_local: int,
	order_ptr_local: int,
	drop_func_idx: int,
	buf: ^[dynamic]u8,
) {
	// save the Order ptr
	emit_instruction(Wasm_Local_Set{index = u32(order_ptr_local)}, buf)

	// trinary = (load8u tag) - 1  (tag 0=Less->-1, 1=Equal->0, 2=Greater->1)
	emit_instruction(Wasm_Local_Get{index = u32(order_ptr_local)}, buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = u32(CAMP_TAG_TAG_OFFSET)}, buf)
	emit_instruction(Wasm_I32_Const{value = 1}, buf)
	emit_instruction(Wasm_I32_Sub{}, buf)
	emit_instruction(Wasm_Local_Set{index = u32(cmp_result_local)}, buf)

	// camp_drop(order_ptr, depth=0)
	emit_instruction(Wasm_Local_Get{index = u32(order_ptr_local)}, buf)
	emit_instruction(Wasm_I32_Const{value = 0}, buf)
	emit_instruction(Wasm_Call{index = u32(drop_func_idx)}, buf)
}

// emit_order_cell_from_trinary constructs an Order heap cell from the trinary
// integer on top of the stack (in {-1,0,1}) and leaves the cell pointer on
// the stack. Trinary -1 -> Less (0), 0 -> Equal (1), 1 -> Greater (2).
// Locals `trinary_local`, `ptr_local`, and `tag_local` are scratch declared
// by the caller.
emit_order_cell_from_trinary :: proc(
	trinary_local: int,
	ptr_local: int,
	tag_local: int,
	alloc_func_idx: int,
	buf: ^[dynamic]u8,
) {
	// stash trinary
	emit_instruction(Wasm_Local_Set{index = u32(trinary_local)}, buf)

	// tag = trinary < 0 ? 0 (Less) : (trinary > 0 ? 2 (Greater) : 1 (Equal))
	emit_instruction(Wasm_Local_Get{index = u32(trinary_local)}, buf)
	emit_instruction(Wasm_I32_Const{value = 0}, buf)
	emit_instruction(Wasm_I32_Lt_S{}, buf)
	emit_instruction(Wasm_If{block_type = .Void}, buf)
	emit_instruction(Wasm_I32_Const{value = 0}, buf) // Less
	emit_instruction(Wasm_Local_Set{index = u32(tag_local)}, buf)
	emit_instruction(Wasm_Else{}, buf)
	emit_instruction(Wasm_Local_Get{index = u32(trinary_local)}, buf)
	emit_instruction(Wasm_I32_Const{value = 0}, buf)
	emit_instruction(Wasm_I32_Gt_S{}, buf)
	emit_instruction(Wasm_If{block_type = .Void}, buf)
	emit_instruction(Wasm_I32_Const{value = 2}, buf) // Greater
	emit_instruction(Wasm_Local_Set{index = u32(tag_local)}, buf)
	emit_instruction(Wasm_Else{}, buf)
	emit_instruction(Wasm_I32_Const{value = 1}, buf) // Equal
	emit_instruction(Wasm_Local_Set{index = u32(tag_local)}, buf)
	emit_instruction(Wasm_End{}, buf)
	emit_instruction(Wasm_End{}, buf)

	// ptr = camp_alloc(CAMP_TAG_HEADER_SIZE)
	emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_HEADER_SIZE)}, buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, buf)
	emit_instruction(Wasm_Local_Set{index = u32(ptr_local)}, buf)

	// refcount = 1
	emit_instruction(Wasm_Local_Get{index = u32(ptr_local)}, buf)
	emit_instruction(Wasm_I32_Const{value = 1}, buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, buf)

	// tag byte
	emit_instruction(Wasm_Local_Get{index = u32(ptr_local)}, buf)
	emit_instruction(Wasm_Local_Get{index = u32(tag_local)}, buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = CAMP_TAG_TAG_OFFSET}, buf)

	// scan_size = 0
	emit_instruction(Wasm_Local_Get{index = u32(ptr_local)}, buf)
	emit_instruction(Wasm_I32_Const{value = 0}, buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = CAMP_TAG_SCAN_SIZE_OFFSET}, buf)

	// scalar_mask = 0
	emit_instruction(Wasm_Local_Get{index = u32(ptr_local)}, buf)
	emit_instruction(Wasm_I32_Const{value = 0}, buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = CAMP_TAG_SCALAR_MASK_OFFSET}, buf)

	// return ptr (left on stack)
	emit_instruction(Wasm_Local_Get{index = u32(ptr_local)}, buf)
}


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
// Returns an Order heap cell (Less/Equal/Greater). Under Design B the
// element compare callbacks return Order cells; when the two Results share
// a tag, Result.compare forwards the callback's Order result directly
// (no drop, no reconstruction). When the tags differ, it constructs a fresh
// Order, so the different-tag case builds Less (Ok<Err) or Greater (Err>Ok).
// Locals: 0=ok_cmp_fn, 1=err_cmp_fn, 2=a, 3=b, 4=tag_a, 5=tag_b,
//         6=trinary, 7=ptr, 8=tag (scratch for Order construction).
emit_result_compare_body :: proc(
	compare_type_idx: int,
	table_idx: int,
	alloc_func_idx: int,
	drop_func_idx: int,
) -> Wasm_Code {
	_ = drop_func_idx // forwarded Order results need no drop here
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
	// Both Ok: forward the ok_cmp_fn Order result (returned, not dropped)
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
	// Both Err: forward the err_cmp_fn Order result (returned, not dropped)
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

	// Different tags: Ok (tag 0) < Err (tag 1)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Lt_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// tag_a < tag_b: a is Ok, b is Err -> Ok < Err -> Less (trinary -1)
	emit_instruction(Wasm_I32_Const{value = -1}, &buf)
	emit_order_cell_from_trinary(6, 7, 8, alloc_func_idx, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	// tag_a > tag_b: a is Err, b is Ok -> Err > Ok -> Greater (trinary 1)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_order_cell_from_trinary(6, 7, 8, alloc_func_idx, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 5,
		type  = .I32,
	} // locals 4-8: tag_a, tag_b, trinary, ptr, tag
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
// Walks two Nil/Cons lists in lockstep. Returns an Order heap cell.
// Under Design B the element compare callback returns an Order cell; this
// body reads its tag (-> trinary -1/0/1) for the loop decision and drops the
// intermediate Order each iteration, then constructs a fresh Order cell for
// the final return value.
// Locals: 0=cmp_fn, 1=current_a, 2=current_b, 3=tag_a, 4=tag_b,
//         5=cmp_trinary, 6=order_ptr, 7=ptr, 8=tag (scratch for Order build).
emit_list_compare_body :: proc(
	compare_type_idx: int,
	table_idx: int,
	alloc_func_idx: int,
	drop_func_idx: int,
) -> Wasm_Code {
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
	// Both Nil: break to the $break block (depth 3: this both-Nil if (0),
	// the Nil-check if (1), the loop (2), the block (3)) so execution falls
	// through to the "return Equal" epilogue. (Previously `br 1`, which only
	// escaped the Nil-check if and wrongly fell into the Cons/b-Nil path.)
	emit_instruction(Wasm_Br{label = 3}, &buf)
	emit_instruction(Wasm_End{}, &buf)
	// a is Nil, b is Cons: a is shorter -> return Less (trinary -1)
	emit_instruction(Wasm_I32_Const{value = -1}, &buf)
	emit_order_cell_from_trinary(5, 7, 8, alloc_func_idx, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// current_a is Cons (tag != 0)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	// a is Cons, b is Nil: b is shorter -> return Greater (trinary 1)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_order_cell_from_trinary(5, 7, 8, alloc_func_idx, &buf)
	emit_instruction(Wasm_Return{}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	// Both Cons: compare head elements. cmp_fn yields an Order cell on the
	// stack; consume it into a trinary (local 5) and drop the intermediate.
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf) // cmp_fn
	emit_instruction(
		Wasm_Call_Indirect{type_idx = u32(compare_type_idx), table_idx = u32(table_idx)},
		&buf,
	)
	consume_order_to_trinary(5, 6, drop_func_idx, &buf)

	// If cmp_fn returned non-zero (i.e. not Equal), construct an Order from
	// the trinary and return it.
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf)
	emit_instruction(Wasm_I32_Eqz{}, &buf) // double eqz = not zero
	emit_instruction(Wasm_If{block_type = .Void}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_order_cell_from_trinary(5, 7, 8, alloc_func_idx, &buf)
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

	// Both lists fully walked with all equal: return Equal (trinary 0)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_order_cell_from_trinary(5, 7, 8, alloc_func_idx, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 1)
	locals[0] = Wasm_Local_Decl {
		count = 6,
		type  = .I32,
	} // locals 3-8: tag_a, tag_b, cmp_trinary, order_ptr, ptr, tag
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

