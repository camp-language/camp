package base

IR_ID :: distinct int
NO_IR_ID :: IR_ID(-1)

IR_Wasm_Type :: enum {
	I32,
	I64,
	F32,
	F64,
	Funcref,
	Void,
}

IR_Type :: struct {
	wasm_type: IR_Wasm_Type,
	type_id:   Type_Var_ID,
	is_heap:   bool,
}

