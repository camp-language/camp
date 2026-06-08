package codegen

// SipHash-1-3 runtime functions for the Hasher type.
//
// Hasher memory layout (52 bytes total = 8-byte header + 44-byte payload):
//   offset 0:  refcount (i32)
//   offset 4:  tag (u8) = HASHER_TAG (0x20)
//   offset 5:  scan_size (u8) = 0 (no heap pointers)
//   offset 6:  scalar_mask (u16) = 0xFF
//   offset 8:  v0 (i64) — SipHash state word 0
//   offset 16: v1 (i64) — SipHash state word 1
//   offset 24: v2 (i64) — SipHash state word 2
//   offset 32: v3 (i64) — SipHash state word 3
//   offset 40: tail (i64) — buffered bytes (little-endian)
//   offset 48: tail_len (i32) — number of bytes in tail (0..7)

HASHER_TAG :: 0x20
HASHER_SIZE :: 52
HASHER_V0_OFFSET :: u32(8)
HASHER_V1_OFFSET :: u32(16)
HASHER_V2_OFFSET :: u32(24)
HASHER_V3_OFFSET :: u32(32)
HASHER_TAIL_OFFSET :: u32(40)
HASHER_TAIL_LEN_OFFSET :: u32(48)

// SipHash constants (key = 0, so k0 ^ C_i = C_i)
SIP_C0 :: u64(0x736f6d6570736575)
SIP_C1 :: u64(0x646f72616e646f6d)
SIP_C2 :: u64(0x6c7967656e657261)
SIP_C3 :: u64(0x7465646279746573)

// emit_sip_round — emit a single SipRound compression round.
// This operates on the SipHash state v0..v3 stored in locals [v0_local, v0_local+3].
// All four locals MUST be i64.
//
// SipRound:
//   v0 += v1;  v2 += v3;
//   v1 = ROTL64(v1, 13);  v3 = ROTL64(v3, 16);
//   v1 ^= v0;  v3 ^= v2;
//   v0 = ROTL64(v0, 32);
//   v0 += v3;  v2 += v1;
//   v1 = ROTL64(v1, 17);  v3 = ROTL64(v3, 21);
//   v1 ^= v3;  v2 ^= v0;
//   v2 = ROTL64(v2, 32);
emit_sip_round :: proc(buf: ^[dynamic]u8, v0_local: u32) {
	v0 := v0_local
	v1 := v0_local + 1
	v2 := v0_local + 2
	v3 := v0_local + 3

	// v0 += v1
	emit_instruction(Wasm_Local_Get{index = v0}, buf)
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_I64_Add{}, buf)
	emit_instruction(Wasm_Local_Set{index = v0}, buf)

	// v2 += v3
	emit_instruction(Wasm_Local_Get{index = v2}, buf)
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_I64_Add{}, buf)
	emit_instruction(Wasm_Local_Set{index = v2}, buf)

	// v1 = ROTL64(v1, 13) = (v1 << 13) | (v1 >>> 51)
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_I64_Const{value = 13}, buf)
	emit_instruction(Wasm_I64_Shl{}, buf)
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_I64_Const{value = 51}, buf)
	emit_instruction(Wasm_I64_Shr_U{}, buf)
	emit_instruction(Wasm_I64_Or{}, buf)
	emit_instruction(Wasm_Local_Set{index = v1}, buf)

	// v3 = ROTL64(v3, 16) = (v3 << 16) | (v3 >>> 48)
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_I64_Const{value = 16}, buf)
	emit_instruction(Wasm_I64_Shl{}, buf)
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_I64_Const{value = 48}, buf)
	emit_instruction(Wasm_I64_Shr_U{}, buf)
	emit_instruction(Wasm_I64_Or{}, buf)
	emit_instruction(Wasm_Local_Set{index = v3}, buf)

	// v1 ^= v0
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_Local_Get{index = v0}, buf)
	emit_instruction(Wasm_I64_Xor{}, buf)
	emit_instruction(Wasm_Local_Set{index = v1}, buf)

	// v3 ^= v2
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_Local_Get{index = v2}, buf)
	emit_instruction(Wasm_I64_Xor{}, buf)
	emit_instruction(Wasm_Local_Set{index = v3}, buf)

	// v0 = ROTL64(v0, 32) = (v0 << 32) | (v0 >>> 32)
	emit_instruction(Wasm_Local_Get{index = v0}, buf)
	emit_instruction(Wasm_I64_Const{value = 32}, buf)
	emit_instruction(Wasm_I64_Shl{}, buf)
	emit_instruction(Wasm_Local_Get{index = v0}, buf)
	emit_instruction(Wasm_I64_Const{value = 32}, buf)
	emit_instruction(Wasm_I64_Shr_U{}, buf)
	emit_instruction(Wasm_I64_Or{}, buf)
	emit_instruction(Wasm_Local_Set{index = v0}, buf)

	// v0 += v3
	emit_instruction(Wasm_Local_Get{index = v0}, buf)
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_I64_Add{}, buf)
	emit_instruction(Wasm_Local_Set{index = v0}, buf)

	// v2 += v1
	emit_instruction(Wasm_Local_Get{index = v2}, buf)
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_I64_Add{}, buf)
	emit_instruction(Wasm_Local_Set{index = v2}, buf)

	// v1 = ROTL64(v1, 17) = (v1 << 17) | (v1 >>> 47)
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_I64_Const{value = 17}, buf)
	emit_instruction(Wasm_I64_Shl{}, buf)
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_I64_Const{value = 47}, buf)
	emit_instruction(Wasm_I64_Shr_U{}, buf)
	emit_instruction(Wasm_I64_Or{}, buf)
	emit_instruction(Wasm_Local_Set{index = v1}, buf)

	// v3 = ROTL64(v3, 21) = (v3 << 21) | (v3 >>> 43)
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_I64_Const{value = 21}, buf)
	emit_instruction(Wasm_I64_Shl{}, buf)
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_I64_Const{value = 43}, buf)
	emit_instruction(Wasm_I64_Shr_U{}, buf)
	emit_instruction(Wasm_I64_Or{}, buf)
	emit_instruction(Wasm_Local_Set{index = v3}, buf)

	// v1 ^= v3
	emit_instruction(Wasm_Local_Get{index = v1}, buf)
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_I64_Xor{}, buf)
	emit_instruction(Wasm_Local_Set{index = v1}, buf)

	// v2 ^= v0
	emit_instruction(Wasm_Local_Get{index = v2}, buf)
	emit_instruction(Wasm_Local_Get{index = v0}, buf)
	emit_instruction(Wasm_I64_Xor{}, buf)
	emit_instruction(Wasm_Local_Set{index = v2}, buf)

	// v2 = ROTL64(v2, 32) = (v2 << 32) | (v2 >>> 32)
	emit_instruction(Wasm_Local_Get{index = v2}, buf)
	emit_instruction(Wasm_I64_Const{value = 32}, buf)
	emit_instruction(Wasm_I64_Shl{}, buf)
	emit_instruction(Wasm_Local_Get{index = v2}, buf)
	emit_instruction(Wasm_I64_Const{value = 32}, buf)
	emit_instruction(Wasm_I64_Shr_U{}, buf)
	emit_instruction(Wasm_I64_Or{}, buf)
	emit_instruction(Wasm_Local_Set{index = v2}, buf)
}

// emit_compress_block — compress an 8-byte block through the SipHash state.
// block_local must be an i64 local holding the block value.
// v0_local..v0_local+3 must be i64 locals holding the SipHash state.
// Implements: v3 ^= block; SipRound(); v0 ^= block;
emit_compress_block :: proc(buf: ^[dynamic]u8, block_local: u32, v0_local: u32) {
	v0 := v0_local
	v3 := v0_local + 3

	// v3 ^= block
	emit_instruction(Wasm_Local_Get{index = v3}, buf)
	emit_instruction(Wasm_Local_Get{index = block_local}, buf)
	emit_instruction(Wasm_I64_Xor{}, buf)
	emit_instruction(Wasm_Local_Set{index = v3}, buf)

	emit_sip_round(buf, v0_local)

	// v0 ^= block
	emit_instruction(Wasm_Local_Get{index = v0}, buf)
	emit_instruction(Wasm_Local_Get{index = block_local}, buf)
	emit_instruction(Wasm_I64_Xor{}, buf)
	emit_instruction(Wasm_Local_Set{index = v0}, buf)
}

// emit_load_state — load SipHash state v0..v3 from hasher pointer into locals.
emit_load_state :: proc(buf: ^[dynamic]u8, hasher_local: u32, v0_local: u32) {
	// v0 = load_i64(hasher + HASHER_V0_OFFSET)
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_V0_OFFSET}, buf)
	emit_instruction(Wasm_Local_Set{index = v0_local}, buf)
	// v1
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_V1_OFFSET}, buf)
	emit_instruction(Wasm_Local_Set{index = v0_local + 1}, buf)
	// v2
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_V2_OFFSET}, buf)
	emit_instruction(Wasm_Local_Set{index = v0_local + 2}, buf)
	// v3
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_V3_OFFSET}, buf)
	emit_instruction(Wasm_Local_Set{index = v0_local + 3}, buf)
}

// emit_store_state — store SipHash state v0..v3 from locals back to hasher memory.
emit_store_state :: proc(buf: ^[dynamic]u8, hasher_local: u32, v0_local: u32) {
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_Local_Get{index = v0_local}, buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V0_OFFSET}, buf)
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_Local_Get{index = v0_local + 1}, buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V1_OFFSET}, buf)
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_Local_Get{index = v0_local + 2}, buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V2_OFFSET}, buf)
	emit_instruction(Wasm_Local_Get{index = hasher_local}, buf)
	emit_instruction(Wasm_Local_Get{index = v0_local + 3}, buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V3_OFFSET}, buf)
}

// Hash_Init: () -> i32
// Allocate a new Hasher and initialize SipHash state.
// Returns the Hasher pointer.
// Params: none
// Locals: 0=hasher_ptr (i32)
emit_hash_init_body :: proc(alloc_func_idx: int) -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_DEFAULT)

	// Allocate HASHER_SIZE bytes
	emit_instruction(Wasm_I32_Const{value = HASHER_SIZE}, &buf)
	emit_instruction(Wasm_Call{index = u32(alloc_func_idx)}, &buf)
	emit_instruction(Wasm_Local_Set{index = 0}, &buf)

	// Set refcount = 1
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = CAMP_TAG_REFCOUNT_OFFSET}, &buf)

	// Set tag = HASHER_TAG
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = HASHER_TAG}, &buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = CAMP_TAG_TAG_OFFSET}, &buf)

	// Set scan_size = 0 (no heap pointers)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = CAMP_TAG_SCAN_SIZE_OFFSET}, &buf)

	// Set scalar_mask = 0xFF (all fields are scalars)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I32_Store8{align = 0, offset = CAMP_TAG_SCALAR_MASK_OFFSET}, &buf)

	// v0 = SIP_C0
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = cast(i64)SIP_C0}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V0_OFFSET}, &buf)

	// v1 = SIP_C1
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = cast(i64)SIP_C1}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V1_OFFSET}, &buf)

	// v2 = SIP_C2
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = cast(i64)SIP_C2}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V2_OFFSET}, &buf)

	// v3 = SIP_C3
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = cast(i64)SIP_C3}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_V3_OFFSET}, &buf)

	// tail = 0
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)

	// tail_len = 0
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)

	// Return hasher pointer
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
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

// Hash_Write_I64: (hasher: i32, val: i64) -> i32
// Write a full 8-byte block. No byte buffering needed.
// Params: 0=hasher, 1=val
// Locals: 2=v0, 3=v1, 4=v2, 5=v3 (all i64)
emit_hash_write_i64_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

	// Load state
	emit_load_state(&buf, 0, 2)

	// Compress block: v3 ^= val; SipRound; v0 ^= val;
	emit_compress_block(&buf, 1, 2)

	// Store state back
	emit_store_state(&buf, 0, 2)

	// Return hasher pointer
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 2)
	locals[0] = Wasm_Local_Decl {
		count = 0,
		type  = .I32,
	} // empty — params only
	locals[1] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	} // v0..v3 (locals 2-5)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// Hash_Write_I32: (hasher: i32, val: i32) -> i32
// Write 4 bytes with tail buffering.
// Params: 0=hasher, 1=val
// Locals: 2=tail (i64), 3=tail_len (i32), 4=v0, 5=v1, 6=v2, 7=v3 (i64)
emit_hash_write_i32_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

	// Load tail
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// Load tail_len
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// val_i64 = i64.extend_i32_u(val)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	// shift = tail_len * 8
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Const{value = 8}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	// shifted = val_i64 << shift
	emit_instruction(Wasm_I64_Shl{}, &buf)
	// tail = tail | shifted
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Or{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// tail_len = tail_len + 4
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 4}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// if tail_len >= 8, compress
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	// Load state
	emit_load_state(&buf, 0, 4)

	// Compress block with tail
	emit_compress_block(&buf, 2, 4)

	// Store state back
	emit_store_state(&buf, 0, 4)

	// tail = 0
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)
	// tail_len = tail_len - 8 (which is 4 - 8 < 0, so 0 since we only added 4 bytes)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if

	// Store tail and tail_len back
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)

	// Return hasher pointer
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	} // tail (local 2)
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // tail_len (local 3)
	locals[2] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	} // v0..v3 (locals 4-7)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// Hash_Write_I16: (hasher: i32, val: i32) -> i32
// Write 2 bytes with tail buffering.
// Params: 0=hasher, 1=val (i32 holding i16 value)
// Locals: 2=tail (i64), 3=tail_len (i32), 4=v0, 5=v1, 6=v2, 7=v3 (i64)
emit_hash_write_i16_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

	// Load tail
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// Load tail_len
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// val_i64 = i64.extend_i32_u(val & 0xFFFF)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFFFF}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	// shift = tail_len * 8
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Const{value = 8}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	// shifted = val_i64 << shift
	emit_instruction(Wasm_I64_Shl{}, &buf)
	// tail = tail | shifted
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Or{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// tail_len = tail_len + 2
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 2}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// if tail_len >= 8, compress (can't happen with just +2, but keep safe)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	emit_load_state(&buf, 0, 4)
	emit_compress_block(&buf, 2, 4)
	emit_store_state(&buf, 0, 4)

	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if

	// Store tail and tail_len back
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	}
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// Hash_Write_I8: (hasher: i32, val: i32) -> i32
// Write 1 byte with tail buffering.
// Params: 0=hasher, 1=val (i32 holding u8 value)
// Locals: 2=tail (i64), 3=tail_len (i32), 4=v0, 5=v1, 6=v2, 7=v3 (i64)
emit_hash_write_i8_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

	// Load tail
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// Load tail_len
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// val_i64 = i64.extend_i32_u(val & 0xFF)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I32_And{}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	// shift = tail_len * 8
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Const{value = 8}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	// shifted = val_i64 << shift
	emit_instruction(Wasm_I64_Shl{}, &buf)
	// tail = tail | shifted
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Or{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// tail_len = tail_len + 1
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// if tail_len >= 8, compress
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	emit_load_state(&buf, 0, 4)
	emit_compress_block(&buf, 2, 4)
	emit_store_state(&buf, 0, 4)

	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	}
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	}
	locals[2] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	}
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// Hash_Write_F64: (hasher: i32, val: f64) -> i32
// Hash a F64 by treating its 8-byte IEEE 754 representation as a full block.
// Params: 0=hasher, 1=val (f64)
// Locals: 2=v0, 3=v1, 4=v2, 5=v3 (i64), 6=bits (i64)
emit_hash_write_f64_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

	// Reinterpret f64 as i64 bits using memory store/load trick
	// Store f64 to temp on stack, load back as i64
	// WASM doesn't have f64.reinterpret/i64, but we can use memory:
	// Allocate 8 bytes on the linear memory at hasher offset 40 (tail field, temporary)
	// Actually, we can use a simpler approach: just use f64.store + i64.load at a scratch area.
	// But we don't have a scratch area. Let's use the hasher's tail field as scratch.
	// After this we'll load the state anyway, so we can overwrite tail.

	// Store f64 bits to hasher+40 (tail field) as temporary
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_F64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)

	// Load back as i64
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Load state
	emit_load_state(&buf, 0, 2)

	// Compress block
	emit_compress_block(&buf, 6, 2)

	// Store state back
	emit_store_state(&buf, 0, 2)

	// Reset tail
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 0,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	} // v0..v3 (locals 2-5)
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	} // bits (local 6)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// Hash_Write_F32: (hasher: i32, val: f32) -> i32
// Hash a F32 by promoting to F64 and compressing as a full 8-byte block.
// This is correct because all F32 values in WASM are represented as 32 bits, and we
// hash the F64 representation after promotion (consistent with how Camp represents F32).
// Params: 0=hasher, 1=val (f32)
// Locals: 2=v0, 3=v1, 4=v2, 5=v3 (i64), 6=bits (i64)
emit_hash_write_f32_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

	// Promote f32 to f64, store to scratch (v0 offset), load back as i64
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_F64_Promote{}, &buf)
	emit_instruction(Wasm_F64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 6}, &buf)

	// Load state
	emit_load_state(&buf, 0, 2)

	// Compress block
	emit_compress_block(&buf, 6, 2)

	// Store state back
	emit_store_state(&buf, 0, 2)

	// Reset tail
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 0,
		type  = .I32,
	}
	locals[1] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	} // v0..v3 (locals 2-5)
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	} // bits (local 6)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// Hash_Write_Str: (hasher: i32, str: i32) -> i32
// Hash a string by processing each byte individually.
// Params: 0=hasher, 1=str (string pointer)
// Locals: 2=str_len (i32), 3=i (i32), 4=tail (i64), 5=tail_len (i32),
//         6=v0, 7=v1, 8=v2, 9=v3 (i64)
emit_hash_write_str_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_XXL)

	// Load string length (at offset 0 of string object)
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// Load tail and tail_len
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// i = 0
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	// Outer block + loop
	emit_instruction(Wasm_Block{block_type = .Void}, &buf) // $break
	emit_instruction(Wasm_Loop{block_type = .Void}, &buf) // $loop

	// if i >= str_len, break
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_Br_If{label = 1}, &buf)

	// byte_i64 = i64.extend_i32_u(load_byte(str + 4 + i))
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_I32_Load8U{align = 0, offset = 4}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	// shift = tail_len * 8
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Const{value = 8}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	// shifted = byte << shift
	emit_instruction(Wasm_I64_Shl{}, &buf)
	// tail = tail | shifted
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I64_Or{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)

	// tail_len++
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// if tail_len >= 8, compress
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Const{value = 8}, &buf)
	emit_instruction(Wasm_I32_Ge_S{}, &buf)
	emit_instruction(Wasm_If{block_type = .Void}, &buf)

	emit_load_state(&buf, 0, 6)
	emit_compress_block(&buf, 4, 6)
	emit_store_state(&buf, 0, 6)

	emit_instruction(Wasm_I64_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 4}, &buf)
	emit_instruction(Wasm_I32_Const{value = 0}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	emit_instruction(Wasm_End{}, &buf) // end if

	// i++
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_I32_Const{value = 1}, &buf)
	emit_instruction(Wasm_I32_Add{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 3}, &buf)

	emit_instruction(Wasm_Br{label = 0}, &buf) // continue loop
	emit_instruction(Wasm_End{}, &buf) // end loop
	emit_instruction(Wasm_End{}, &buf) // end block

	// Store tail and tail_len back
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I64_Store{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I32_Store{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)

	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 4)
	locals[0] = Wasm_Local_Decl {
		count = 2,
		type  = .I32,
	} // str_len, i (locals 2,3)
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	} // tail (local 4)
	locals[2] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // tail_len (local 5)
	locals[3] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	} // v0..v3 (locals 6-9)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

// Hash_Finish: (hasher: i32) -> i64
// Finalize SipHash and return the 64-bit hash value.
// Params: 0=hasher
// Locals: 1=tail (i64), 2=tail_len (i32), 3=v0, 4=v1, 5=v2, 6=v3 (i64)
emit_hash_finish_body :: proc() -> Wasm_Code {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_MAJOR)

	// Load tail
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I64_Load{align = 3, offset = HASHER_TAIL_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// Load tail_len
	emit_instruction(Wasm_Local_Get{index = 0}, &buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = HASHER_TAIL_LEN_OFFSET}, &buf)
	emit_instruction(Wasm_Local_Set{index = 2}, &buf)

	// Pad tail: tail |= (0xFF << (tail_len * 8))
	emit_instruction(Wasm_Local_Get{index = 1}, &buf)
	emit_instruction(Wasm_I64_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_Local_Get{index = 2}, &buf)
	emit_instruction(Wasm_I64_Extend_I32_S{}, &buf)
	emit_instruction(Wasm_I64_Const{value = 8}, &buf)
	emit_instruction(Wasm_I64_Mul{}, &buf)
	emit_instruction(Wasm_I64_Shl{}, &buf)
	emit_instruction(Wasm_I64_Or{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 1}, &buf)

	// Load state
	emit_load_state(&buf, 0, 3)

	// Final compression: v3 ^= tail; SipRound; v0 ^= tail;
	emit_compress_block(&buf, 1, 3)

	// Finalization: v2 ^= 0xFF
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I64_Const{value = 0xFF}, &buf)
	emit_instruction(Wasm_I64_Xor{}, &buf)
	emit_instruction(Wasm_Local_Set{index = 5}, &buf)

	// 3 finalization rounds
	emit_sip_round(&buf, 3)
	emit_sip_round(&buf, 3)
	emit_sip_round(&buf, 3)

	// result = v0 ^ v1 ^ v2 ^ v3
	emit_instruction(Wasm_Local_Get{index = 3}, &buf)
	emit_instruction(Wasm_Local_Get{index = 4}, &buf)
	emit_instruction(Wasm_I64_Xor{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 5}, &buf)
	emit_instruction(Wasm_I64_Xor{}, &buf)
	emit_instruction(Wasm_Local_Get{index = 6}, &buf)
	emit_instruction(Wasm_I64_Xor{}, &buf)

	emit_instruction(Wasm_End{}, &buf)

	locals := make([]Wasm_Local_Decl, 3)
	locals[0] = Wasm_Local_Decl {
		count = 1,
		type  = .I64,
	} // tail (local 1)
	locals[1] = Wasm_Local_Decl {
		count = 1,
		type  = .I32,
	} // tail_len (local 2)
	locals[2] = Wasm_Local_Decl {
		count = 4,
		type  = .I64,
	} // v0..v3 (locals 3-6)
	body := make([]u8, len(buf))
	for b, i in buf {body[i] = b}
	delete(buf)
	return Wasm_Code{locals = locals, body = body}
}

