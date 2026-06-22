package camp

import "camp:codegen"
import "core:testing"

@(test)
test_scan_empty_body :: proc(t: ^testing.T) {
	body: []u8
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 0, "empty body should have no call targets")
	delete(targets)
}

@(test)
test_scan_single_call :: proc(t: ^testing.T) {
	// call 42 => 0x10, 0x2A
	body := []u8{0x10, 0x2A}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 1, "expected 1 call target")
	testing.expect(t, targets[0] == 42, "expected func_idx 42")
	delete(targets)
}

@(test)
test_scan_call_with_large_index :: proc(t: ^testing.T) {
	// call 300 => 0x10, 0xAC, 0x02 (LEB128 encoding of 300)
	body := []u8{0x10, 0xAC, 0x02}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 1, "expected 1 call target")
	testing.expect(t, targets[0] == 300, "expected func_idx 300")
	delete(targets)
}

@(test)
test_scan_call_between_other_instructions :: proc(t: ^testing.T) {
	// i32.const 7 => 0x41, 0x07
	// call 5     => 0x10, 0x05
	// drop       => 0x1A
	// end        => 0x0B
	body := []u8{0x41, 0x07, 0x10, 0x05, 0x1A, 0x0B}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 1, "expected 1 call target")
	testing.expect(t, targets[0] == 5, "expected func_idx 5")
	delete(targets)
}

@(test)
test_scan_no_false_positive_from_i32_const :: proc(t: ^testing.T) {
	// i32.const 16 => 0x41, 0x10
	// The 0x10 here is NOT a call opcode — it's the LEB128 value 16.
	body := []u8{0x41, 0x10, 0x0B}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 0, "i32.const 16 should not produce a call target")
	delete(targets)
}

@(test)
test_scan_multiple_calls :: proc(t: ^testing.T) {
	// call 1  => 0x10, 0x01
	// call 2  => 0x10, 0x02
	// call 3  => 0x10, 0x03
	// end     => 0x0B
	body := []u8{0x10, 0x01, 0x10, 0x02, 0x10, 0x03, 0x0B}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 3, "expected 3 call targets")
	testing.expect(t, targets[0] == 1, "expected func_idx 1")
	testing.expect(t, targets[1] == 2, "expected func_idx 2")
	testing.expect(t, targets[2] == 3, "expected func_idx 3")
	delete(targets)
}

@(test)
test_scan_i64_const_does_not_interfere :: proc(t: ^testing.T) {
	// i64.const 255 => 0x42, 0xFF, 0x01
	// call 10       => 0x10, 0x0A
	// end           => 0x0B
	body := []u8{0x42, 0xFF, 0x01, 0x10, 0x0A, 0x0B}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 1, "expected 1 call target")
	testing.expect(t, targets[0] == 10, "expected func_idx 10")
	delete(targets)
}

@(test)
test_scan_memory_ops :: proc(t: ^testing.T) {
	// i32.load align=2 offset=0 => 0x28, 0x02, 0x00
	// call 7                    => 0x10, 0x07
	// end                       => 0x0B
	body := []u8{0x28, 0x02, 0x00, 0x10, 0x07, 0x0B}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 1, "expected 1 call target")
	testing.expect(t, targets[0] == 7, "expected func_idx 7")
	delete(targets)
}

@(test)
test_scan_f32_const :: proc(t: ^testing.T) {
	// f32.const (4 bytes) then call
	// f32.const => 0x43, 0x00, 0x00, 0x80, 0x3F  (1.0f)
	// call 3    => 0x10, 0x03
	// end       => 0x0B
	body := []u8{0x43, 0x00, 0x00, 0x80, 0x3F, 0x10, 0x03, 0x0B}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 1, "expected 1 call target")
	testing.expect(t, targets[0] == 3, "expected func_idx 3")
	delete(targets)
}

@(test)
test_scan_call_indirect :: proc(t: ^testing.T) {
	// call_indirect type=0 table=0 => 0x11, 0x00, 0x00
	// call 5                       => 0x10, 0x05
	// end                          => 0x0B
	body := []u8{0x11, 0x00, 0x00, 0x10, 0x05, 0x0B}
	targets := codegen.scan_calls_in_bytecode(body)
	testing.expect(t, len(targets) == 1, "expected 1 call target (not call_indirect)")
	testing.expect(t, targets[0] == 5, "expected func_idx 5")
	delete(targets)
}

