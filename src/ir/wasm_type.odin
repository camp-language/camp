package ir

import "camp:base"

ir_expr_wasm_type :: proc(expr: IR_Expr) -> base.IR_Wasm_Type {
	if expr == nil do return .I32
	#partial switch e in expr {
	case ^IR_Literal_Int:
		return e.type.wasm_type
	case ^IR_Literal_Float:
		return e.type.wasm_type
	case ^IR_Literal_Bool:
		return .I32
	case ^IR_Literal_String:
		return .I32
	case ^IR_Var:
		return e.type.wasm_type
	case ^IR_Let:
		return ir_expr_wasm_type(e.body)
	case ^IR_Assign:
		return e.type.wasm_type
	case ^IR_Loop:
		return e.type.wasm_type
	case ^IR_Call:
		return e.type.wasm_type
	case ^IR_Tail_Call:
		return .Void
	case ^IR_If:
		return e.type.wasm_type
	case ^IR_Match:
		return e.type.wasm_type
	case ^IR_Construct_Tag:
		return .I32
	case ^IR_Construct_Record:
		return .I32
	case ^IR_Construct_Tuple:
		return .I32
	case ^IR_Field_Access:
		return e.type.wasm_type
	case ^IR_BinOp:
		return e.type.wasm_type
	case ^IR_Closure:
		return .I32
	case ^IR_Closure_Call:
		return e.type.wasm_type
	case ^IR_Resume:
		return e.type.wasm_type
	case ^IR_Atomic_Load:
		return .I32
	case ^IR_Atomic_RMW:
		return .I32
	case ^IR_Atomic_Fence:
		return .Void
	case ^IR_Wait:
		return .I32
	case ^IR_Notify:
		return .I32
	case ^IR_Method_Call:
		return e.type.wasm_type
	case ^IR_Handle:
		return e.type.wasm_type
	case ^IR_Perform:
		return e.type.wasm_type
	case ^IR_Block:
		return e.type.wasm_type
	case ^IR_Dup:
		return .I32
	case ^IR_Drop, ^IR_Return, ^IR_Crash, ^IR_I32_Store, ^IR_Atomic_Store:
		return .Void
	case ^IR_Expr_Nominal_Construct, ^IR_I32_Load:
		return .I32
	}
	return .I32
}

// ir_expr_is_heap reports whether an expression evaluates to a heap pointer that the
// Perceus drop routine must recurse into. This is distinct from the wasm type: bools,
// function indices, and i64/f64 scalars are not heap pointers even though some are i32.
ir_expr_is_heap :: proc(expr: IR_Expr) -> bool {
	if expr == nil do return false
	#partial switch e in expr {
	case ^IR_Literal_Int, ^IR_Literal_Float, ^IR_Literal_Bool:
		return false
	case ^IR_Literal_String:
		return true
	case ^IR_Construct_Tag,
	     ^IR_Construct_Record,
	     ^IR_Construct_Tuple,
	     ^IR_Closure,
	     ^IR_Expr_Nominal_Construct:
		return true
	case ^IR_Var:
		return e.type.is_heap
	case ^IR_Let:
		return ir_expr_is_heap(e.body)
	case ^IR_Assign:
		return e.type.is_heap
	case ^IR_Loop:
		return e.type.is_heap
	case ^IR_Call:
		return e.type.is_heap
	case ^IR_If:
		return e.type.is_heap
	case ^IR_Match:
		return e.type.is_heap
	case ^IR_Field_Access:
		return e.type.is_heap
	case ^IR_BinOp:
		return e.type.is_heap
	case ^IR_Closure_Call:
		return e.type.is_heap
	case ^IR_Resume:
		return e.type.is_heap
	case ^IR_Method_Call:
		return e.type.is_heap
	case ^IR_Handle:
		return e.type.is_heap
	case ^IR_Perform:
		return e.type.is_heap
	case ^IR_Block:
		return e.type.is_heap
	}
	// Raw/atomic ops, tail calls, voids, and anything unhandled: treat as non-heap so
	// drop does not dereference them. (Genuine heap producers are listed above.)
	return false
}

