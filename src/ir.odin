package camp

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
}

IR_Module :: struct {
	decls:        [dynamic]IR_Decl,
	effect_defs:  [dynamic]IR_Effect_Def,
	string_table: [dynamic]String_Table_Entry,
}

String_Table_Entry :: struct {
	id:    Intern_ID,
	value: string,
}

IR_Decl :: union {
	^IR_Decl_Fn,
	^IR_Decl_Const,
	^IR_Decl_Effect,
}

IR_Decl_Fn :: struct {
	name:         Canonical_Name,
	is_effectful: bool,
	params:       [dynamic]IR_Param,
	return_type:  IR_Type,
	effect_row:   IR_Type,
	body:         IR_Expr,
	span:         Source_Span,
}

IR_Param :: struct {
	name: Intern_ID,
	type: IR_Type,
}

IR_Decl_Const :: struct {
	name:  Canonical_Name,
	type:  IR_Type,
	value: IR_Expr,
	span:  Source_Span,
}

IR_Decl_Effect :: struct {
	name:       Canonical_Name,
	operations: [dynamic]IR_Effect_Op,
	span:       Source_Span,
}

IR_Effect_Op :: struct {
	name:        Intern_ID,
	params:      [dynamic]IR_Param,
	return_type: IR_Type,
}

IR_Effect_Def :: struct {
	name:       Canonical_Name,
	operations: [dynamic]IR_Effect_Op,
}

IR_Expr :: union {
	^IR_Literal_Int,
	^IR_Literal_Float,
	^IR_Literal_String,
	^IR_Literal_Bool,
	^IR_Var,
	^IR_Let,
	^IR_Call,
	^IR_Tail_Call,
	^IR_If,
	^IR_Match,
	^IR_Construct_Tag,
	^IR_Construct_Record,
	^IR_Field_Access,
	^IR_Method_Call,
	^IR_Handle,
	^IR_Perform,
	^IR_Closure,
	^IR_Return,
	^IR_Block,
	^IR_BinOp,
	^IR_Dup,
	^IR_Drop,
	^IR_Drop_Reuse,
	^IR_Alloc_At,
}

IR_Literal_Int :: struct { value: i64, type: IR_Type, span: Source_Span }
IR_Literal_Float :: struct { value: f64, type: IR_Type, span: Source_Span }
IR_Literal_String :: struct { value: string, type: IR_Type, span: Source_Span }
IR_Literal_Bool :: struct { value: bool, type: IR_Type, span: Source_Span }

IR_Var :: struct { name: Intern_ID, type: IR_Type, span: Source_Span }

IR_Let :: struct {
	binding: Intern_ID,
	type:    IR_Type,
	value:   IR_Expr,
	body:    IR_Expr,
	span:    Source_Span,
}

IR_Call :: struct {
	callee: Canonical_Name,
	args:   [dynamic]IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Tail_Call :: struct {
	callee: Canonical_Name,
	args:   [dynamic]IR_Expr,
	span:   Source_Span,
}

IR_If :: struct {
	condition:   IR_Expr,
	then_branch: IR_Expr,
	else_branch: IR_Expr,
	type:        IR_Type,
	span:        Source_Span,
}

IR_Match :: struct {
	scrutinee: IR_Expr,
	arms:      [dynamic]IR_Match_Arm,
	type:      IR_Type,
	span:      Source_Span,
}

IR_Match_Arm :: struct {
	pattern: IR_Pattern,
	body:    IR_Expr,
}

IR_Pattern :: union {
	^IR_Pat_Tag,
	^IR_Pat_Record,
	^IR_Pat_Var,
	^IR_Pat_Wildcard,
}

IR_Pat_Tag :: struct { name: Intern_ID, payload: [dynamic]Intern_ID }
IR_Pat_Record :: struct { fields: [dynamic]IR_Pat_Field, is_open: bool }
IR_Pat_Field :: struct { name: Intern_ID, binding: Intern_ID }
IR_Pat_Var :: struct { name: Intern_ID }
IR_Pat_Wildcard :: struct {}

IR_Construct_Tag :: struct {
	tag_name: Intern_ID,
	payload:  [dynamic]IR_Expr,
	type:     IR_Type,
	span:     Source_Span,
}

IR_Construct_Record :: struct {
	fields: [dynamic]IR_Record_Field,
	rest:   IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Record_Field :: struct { name: Intern_ID, value: IR_Expr }

IR_Field_Access :: struct { record: IR_Expr, field: Intern_ID, type: IR_Type, span: Source_Span }

IR_Method_Call :: struct {
	receiver: IR_Expr,
	method:   Intern_ID,
	args:     [dynamic]IR_Expr,
	type:     IR_Type,
	span:     Source_Span,
}

IR_Handle :: struct {
	effect:     Canonical_Name,
	is_shallow: bool,
	body:       IR_Expr,
	arms:       [dynamic]IR_Handler_Arm,
	type:       IR_Type,
	span:       Source_Span,
}

IR_Handler_Arm :: struct {
	op:        Intern_ID,
	resume_id: Intern_ID,
	body:      IR_Expr,
}

IR_Perform :: struct {
	effect: Canonical_Name,
	op:     Intern_ID,
	args:   [dynamic]IR_Expr,
	type:   IR_Type,
	span:   Source_Span,
}

IR_Closure :: struct {
	fn_name: Canonical_Name,
	env:     IR_Expr,
	body:    IR_Expr,
	type:    IR_Type,
	span:    Source_Span,
}

IR_Return :: struct { value: IR_Expr, span: Source_Span }

IR_Block :: struct { statements: [dynamic]IR_Expr, type: IR_Type, span: Source_Span }

IR_BinOp :: struct { op: Token_Kind, left: IR_Expr, right: IR_Expr, type: IR_Type, span: Source_Span }

IR_Dup :: struct { value: Intern_ID, span: Source_Span }
IR_Drop :: struct { value: Intern_ID, span: Source_Span }
IR_Drop_Reuse :: struct { value: Intern_ID, reuse_as: Intern_ID, span: Source_Span }
IR_Alloc_At :: struct { value: Intern_ID, at: Intern_ID, span: Source_Span }
