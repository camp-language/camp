package codegen

// WASM bytecode scanner for identifying call targets.
// Used by runtime pruning to detect which runtime functions are
// transitively reachable from emitted code.

read_uleb128 :: proc(data: []u8, offset: int) -> (value: u32, new_offset: int) {
	shift: u32
	pos := offset
	for pos < len(data) {
		b := data[pos]
		pos += 1
		value |= u32(b & 0x7F) << shift
		if b & 0x80 == 0 {
			new_offset = pos
			return
		}
		shift += 7
	}
	new_offset = pos
	return
}

skip_uleb128 :: proc(data: []u8, offset: int) -> int {
	pos := offset
	for pos < len(data) {
		b := data[pos]
		pos += 1
		if b & 0x80 == 0 {
			return pos
		}
	}
	return pos
}

// has_call_indirect_in_bytecode returns true if the WASM bytecode
// contains any call_indirect (0x11) instructions.
has_call_indirect_in_bytecode :: proc(body: []u8) -> bool {
	pos := 0
	for pos < len(body) {
		opcode := body[pos]
		pos += 1

		if opcode == 0x11 {
			return true
		}

		// Skip immediates based on opcode (same logic as scan_calls_in_bytecode)
		if opcode == 0x02 || opcode == 0x03 || opcode == 0x04 {
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x0C || opcode == 0x0D {
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x0E {
			n_labels: u32
			n_labels, pos = read_uleb128(body, pos)
			for _ in 0 ..< int(n_labels) + 1 {
				pos = skip_uleb128(body, pos)
			}
		} else if opcode == 0x10 || opcode == 0x11 {
			pos = skip_uleb128(body, pos)
			if opcode == 0x11 {
				pos = skip_uleb128(body, pos)
			}
		} else if opcode >= 0x20 && opcode <= 0x26 {
			pos = skip_uleb128(body, pos)
		} else if opcode >= 0x28 && opcode <= 0x3E {
			pos = skip_uleb128(body, pos)
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x3F || opcode == 0x40 {
			if pos < len(body) {pos += 1}
		} else if opcode == 0x41 || opcode == 0x42 {
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x43 {
			pos += 4
		} else if opcode == 0x44 {
			pos += 8
		} else if opcode == 0xD0 || opcode == 0xD2 {
			pos = skip_uleb128(body, pos)
		} else if opcode == 0xFC {
			sub_op: u32
			sub_op, pos = read_uleb128(body, pos)
			if sub_op == 8 {
				pos = skip_uleb128(body, pos); pos += 1
			} else if sub_op == 9 || sub_op == 13 {
				pos = skip_uleb128(body, pos)
			} else if sub_op ==
			   10 {pos += 2} else if sub_op == 11 {pos += 1} else if sub_op == 12 || sub_op == 14 {
				pos = skip_uleb128(body, pos); pos = skip_uleb128(body, pos)
			} else if sub_op >= 15 {pos = skip_uleb128(body, pos)}
		} else if opcode == 0xFD {
			return true // conservative: SIMD may contain call_indirect
		}
	}
	return false
}

// has_any_call_indirect scans all code entries for call_indirect.
has_any_call_indirect :: proc(mod: ^Wasm_Module) -> bool {
	for code in mod.codes {
		if has_call_indirect_in_bytecode(code.body) {
			return true
		}
	}
	return false
}

// scan_calls_in_bytecode walks WASM bytecode and returns all function
// indices targeted by `call` (0x10) instructions. Handles all standard
// WASM instruction opcodes to correctly track instruction boundaries.
scan_calls_in_bytecode :: proc(body: []u8) -> [dynamic]u32 {
	calls: [dynamic]u32
	pos := 0

	for pos < len(body) {
		opcode := body[pos]
		pos += 1

		// Instructions with no immediates
		if opcode == 0x00 ||
		   opcode == 0x01 ||
		   opcode == 0x05 ||
		   opcode == 0x0B ||
		   opcode == 0x0F ||
		   opcode == 0x1A ||
		   opcode == 0x1B ||
		   opcode == 0xD1 ||
		   opcode == 0xD3 {
			// unreachable, nop, else, end, return, drop, select,
			// ref.is_null, ref.as_non_null
		} else if opcode == 0x02 || opcode == 0x03 || opcode == 0x04 {
			// block, loop, if — block type immediate
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x0C || opcode == 0x0D {
			// br, br_if — label index
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x0E {
			// br_table — nlabels + labels + default
			n_labels: u32
			n_labels, pos = read_uleb128(body, pos)
			for _ in 0 ..< int(n_labels) + 1 {
				pos = skip_uleb128(body, pos)
			}
		} else if opcode == 0x10 {
			// call — the opcode we're looking for
			func_idx: u32
			func_idx, pos = read_uleb128(body, pos)
			append(&calls, func_idx)
		} else if opcode == 0x11 {
			// call_indirect — typeidx + tableidx
			pos = skip_uleb128(body, pos)
			pos = skip_uleb128(body, pos)
		} else if opcode >= 0x20 && opcode <= 0x24 {
			// local.get/set/tee, global.get/set — index
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x25 || opcode == 0x26 {
			// table.get, table.set — table index
			pos = skip_uleb128(body, pos)
		} else if opcode >= 0x28 && opcode <= 0x3E {
			// memory load/store — align + offset
			pos = skip_uleb128(body, pos)
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x3F || opcode == 0x40 {
			// memory.size, memory.grow — reserved byte
			if pos < len(body) {
				pos += 1
			}
		} else if opcode == 0x41 {
			// i32.const — LEB128 i32
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x42 {
			// i64.const — LEB128 i64
			pos = skip_uleb128(body, pos)
		} else if opcode == 0x43 {
			// f32.const — 4 raw bytes
			pos += 4
		} else if opcode == 0x44 {
			// f64.const — 8 raw bytes
			pos += 8
		} else if opcode == 0xD0 {
			// ref.null — type index
			pos = skip_uleb128(body, pos)
		} else if opcode == 0xD2 {
			// ref.func — function index
			pos = skip_uleb128(body, pos)
		} else if opcode == 0xFC {
			// saturating truncation / bulk memory / table ops
			sub_op: u32
			sub_op, pos = read_uleb128(body, pos)
			if sub_op <= 7 {
				// i32/i64 trunc_sat — no further immediates
			} else if sub_op == 8 {
				// memory.init — data_idx + 0x00
				pos = skip_uleb128(body, pos)
				pos += 1
			} else if sub_op == 9 {
				// data.drop — data_idx
				pos = skip_uleb128(body, pos)
			} else if sub_op == 10 {
				// memory.copy — 0x00 + 0x00
				pos += 2
			} else if sub_op == 11 {
				// memory.fill — 0x00
				pos += 1
			} else if sub_op == 12 {
				// table.init — elem_idx + table_idx
				pos = skip_uleb128(body, pos)
				pos = skip_uleb128(body, pos)
			} else if sub_op == 13 {
				// elem.drop — elem_idx
				pos = skip_uleb128(body, pos)
			} else if sub_op == 14 {
				// table.copy — dst_table + src_table
				pos = skip_uleb128(body, pos)
				pos = skip_uleb128(body, pos)
			} else {
				// table.grow/size/fill — table_idx
				pos = skip_uleb128(body, pos)
			}
		} else if opcode == 0xFD {
			// SIMD — sub-opcode + variable immediates
			// Camp doesn't emit SIMD; stop scanning to be safe
			return calls
		}
		// All other opcodes (0x45-0xCF, 0xD4-0xFB): no immediates
	}

	return calls
}

