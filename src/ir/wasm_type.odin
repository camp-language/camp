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

