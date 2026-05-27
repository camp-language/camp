package ir

import ba "camp:base"

NO_REUSE_ADDR :: ba.Intern_ID(-1)

IR_Module :: struct {
	decls:        [dynamic]IR_Decl,
	effect_defs:  [dynamic]IR_Effect_Def,
	string_table: [dynamic]String_Table_Entry,
}

String_Table_Entry :: struct {
	id:    ba.Intern_ID,
	value: string,
}

IR_Decl :: union {
	^IR_Decl_Fn,
	^IR_Decl_Const,
	^IR_Decl_Effect,
}

IR_Decl_Fn :: struct {
	name:         ba.Canonical_Name,
	is_effectful: bool,
	params:       [dynamic]IR_Param,
	return_type:  ba.IR_Type,
	effect_row:   ba.IR_Type,
	effects:      [dynamic]ba.Canonical_Name,
	body:         IR_Expr,
	span:         ba.Source_Span,
}

IR_Param :: struct {
	name: ba.Intern_ID,
	type: ba.IR_Type,
}

IR_Decl_Const :: struct {
	name:  ba.Canonical_Name,
	type:  ba.IR_Type,
	value: IR_Expr,
	span:  ba.Source_Span,
}

IR_Decl_Effect :: struct {
	name:       ba.Canonical_Name,
	operations: [dynamic]IR_Effect_Op,
	span:       ba.Source_Span,
}

IR_Effect_Op :: struct {
	name:        ba.Intern_ID,
	params:      [dynamic]IR_Param,
	return_type: ba.IR_Type,
}

IR_Effect_Def :: struct {
	name:        ba.Canonical_Name,
	operations:  [dynamic]IR_Effect_Op,
	type_params: [dynamic]ba.Intern_ID,
}

Atomic_Width :: enum {
	B1,
	B2,
	B4,
	B8,
}

Atomic_Op :: enum {
	Add,
	Sub,
	And,
	Or,
	Xor,
	Xchg,
	CmpXchg,
}

IR_Atomic_Load :: struct {
	base:   IR_Expr,
	offset: int,
	width:  Atomic_Width,
	span:   ba.Source_Span,
}

IR_Atomic_Store :: struct {
	base:   IR_Expr,
	offset: int,
	value:  IR_Expr,
	width:  Atomic_Width,
	span:   ba.Source_Span,
}

IR_Atomic_RMW :: struct {
	base:   IR_Expr,
	offset: int,
	value:  IR_Expr,
	op:     Atomic_Op,
	width:  Atomic_Width,
	span:   ba.Source_Span,
}

IR_Atomic_Fence :: struct {
	span: ba.Source_Span,
}

IR_Wait :: struct {
	base:     IR_Expr,
	offset:   int,
	expected: IR_Expr,
	timeout:  IR_Expr,
	width:    Atomic_Width,
	span:     ba.Source_Span,
}

IR_Notify :: struct {
	base:   IR_Expr,
	offset: int,
	count:  IR_Expr,
	span:   ba.Source_Span,
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
	^IR_Expr_Nominal_Construct,
	^IR_Construct_Record,
	^IR_Construct_Tuple,
	^IR_Field_Access,
	^IR_Method_Call,
	^IR_Handle,
	^IR_Perform,
	^IR_Resume,
	^IR_Closure,
	^IR_Closure_Call,
	^IR_Return,
	^IR_Block,
	^IR_BinOp,
	^IR_Dup,
	^IR_Drop,
	^IR_Crash,
	^IR_I32_Load,
	^IR_I32_Store,
	^IR_Atomic_Load,
	^IR_Atomic_Store,
	^IR_Atomic_RMW,
	^IR_Atomic_Fence,
	^IR_Wait,
	^IR_Notify,
	^IR_Assign,
	^IR_Loop,
}

IR_Literal_Int :: struct {
	value: i64,
	type:  ba.IR_Type,
	span:  ba.Source_Span,
}
IR_Literal_Float :: struct {
	value: f64,
	type:  ba.IR_Type,
	span:  ba.Source_Span,
}
IR_Literal_String :: struct {
	value: string,
	type:  ba.IR_Type,
	span:  ba.Source_Span,
}
IR_Literal_Bool :: struct {
	value: bool,
	type:  ba.IR_Type,
	span:  ba.Source_Span,
}

IR_Var :: struct {
	name: ba.Intern_ID,
	type: ba.IR_Type,
	span: ba.Source_Span,
}

IR_Let :: struct {
	binding: ba.Intern_ID,
	type:    ba.IR_Type,
	value:   IR_Expr,
	body:    IR_Expr,
	span:    ba.Source_Span,
}

IR_Assign :: struct {
	binding: ba.Intern_ID,
	value:   IR_Expr,
	type:    ba.IR_Type,
	span:    ba.Source_Span,
}

IR_Loop :: struct {
	var:      ba.Intern_ID,
	iterable: IR_Expr,
	body:     IR_Expr,
	type:     ba.IR_Type,
	span:     ba.Source_Span,
}

IR_Call :: struct {
	callee:           ba.Canonical_Name,
	args:             [dynamic]IR_Expr,
	type:             ba.IR_Type,
	span:             ba.Source_Span,
	ord_compare_func: ba.Canonical_Name,
}

IR_Tail_Call :: struct {
	callee: ba.Canonical_Name,
	args:   [dynamic]IR_Expr,
	span:   ba.Source_Span,
}

IR_If :: struct {
	condition:   IR_Expr,
	then_branch: IR_Expr,
	else_branch: IR_Expr,
	type:        ba.IR_Type,
	span:        ba.Source_Span,
}

IR_Match :: struct {
	scrutinee: IR_Expr,
	arms:      [dynamic]IR_Match_Arm,
	type:      ba.IR_Type,
	span:      ba.Source_Span,
}

IR_Match_Arm :: struct {
	pattern: IR_Pattern,
	guard:   IR_Expr, // nil when the arm has no `if` guard
	body:    IR_Expr,
}

IR_Pattern :: union {
	^IR_Pat_Tag,
	^IR_Pat_Record,
	^IR_Pat_Var,
	^IR_Pat_Wildcard,
	^IR_Pat_Bool,
	^IR_Pat_Int,
	^IR_Pat_String,
	^IR_Pat_Tuple,
}

IR_Pat_Tag :: struct {
	name:               ba.Intern_ID,
	tag_index:          int,
	payload:            [dynamic]ba.Intern_ID,
	payload_wasm_types: []ba.IR_Wasm_Type,
}
IR_Pat_Record :: struct {
	fields:  [dynamic]IR_Pat_Field,
	is_open: bool,
}
IR_Pat_Field :: struct {
	name:        ba.Intern_ID,
	binding:     ba.Intern_ID,
	field_index: int,
	wasm_type:   ba.IR_Wasm_Type,
}
IR_Pat_Tuple_Element :: struct {
	binding:     ba.Intern_ID,
	field_index: int,
	wasm_type:   ba.IR_Wasm_Type,
}
IR_Pat_Tuple :: struct {
	elements: [dynamic]IR_Pat_Tuple_Element,
	span:     ba.Source_Span,
}
IR_Pat_Var :: struct {
	name: ba.Intern_ID,
}
IR_Pat_Wildcard :: struct {}
IR_Pat_Bool :: struct {
	value: bool,
}
IR_Pat_Int :: struct {
	value: i64,
}
IR_Pat_String :: struct {
	string_id: ba.Intern_ID,
}

IR_Construct_Tag :: struct {
	tag_name:   ba.Intern_ID,
	tag_index:  int,
	payload:    [dynamic]IR_Expr,
	reuse_addr: ba.Intern_ID,
	type:       ba.IR_Type,
	span:       ba.Source_Span,
}

IR_Expr_Nominal_Construct :: struct {
	type_name: ba.Canonical_Name,
	variant:   ba.Intern_ID, // 0 = simple wrap, non-zero = qualified variant
	payload:   [dynamic]IR_Expr,
	span:      ba.Source_Span,
}

IR_Construct_Record :: struct {
	fields:     [dynamic]IR_Record_Field,
	rest:       IR_Expr,
	reuse_addr: ba.Intern_ID,
	type:       ba.IR_Type,
	span:       ba.Source_Span,
}
IR_Construct_Tuple :: struct {
	elements:   [dynamic]IR_Expr,
	reuse_addr: ba.Intern_ID,
	type:       ba.IR_Type,
	span:       ba.Source_Span,
}

IR_Record_Field :: struct {
	name:  ba.Intern_ID,
	value: IR_Expr,
}

IR_Field_Access :: struct {
	record:      IR_Expr,
	field:       ba.Intern_ID,
	field_index: int,
	type:        ba.IR_Type,
	span:        ba.Source_Span,
}

IR_Method_Call :: struct {
	receiver: IR_Expr,
	method:   ba.Intern_ID,
	args:     [dynamic]IR_Expr,
	type:     ba.IR_Type,
	span:     ba.Source_Span,
}

IR_Handle :: struct {
	effects: [dynamic]ba.Canonical_Name,
	body:    IR_Expr,
	arms:    [dynamic]IR_Handler_Arm,
	type:    ba.IR_Type,
	span:    ba.Source_Span,
}

IR_Handler_Arm :: struct {
	op:     ba.Intern_ID,
	params: [dynamic]ba.Intern_ID,
	body:   IR_Expr,
}

IR_Perform :: struct {
	effect: ba.Canonical_Name,
	op:     ba.Intern_ID,
	args:   [dynamic]IR_Expr,
	type:   ba.IR_Type,
	span:   ba.Source_Span,
}

IR_Resume :: struct {
	resume_id: ba.Intern_ID,
	value:     IR_Expr,
	ev:        IR_Expr,
	type:      ba.IR_Type,
	span:      ba.Source_Span,
}

IR_Closure :: struct {
	fn_name:     ba.Canonical_Name,
	params:      [dynamic]IR_Param,
	env:         IR_Expr,
	body:        IR_Expr,
	type:        ba.IR_Type,
	return_type: ba.IR_Type,
	span:        ba.Source_Span,
}

IR_Closure_Call :: struct {
	callee: IR_Expr,
	args:   [dynamic]IR_Expr,
	type:   ba.IR_Type,
	span:   ba.Source_Span,
}

IR_Return :: struct {
	value: IR_Expr,
	span:  ba.Source_Span,
}

IR_Block :: struct {
	statements: [dynamic]IR_Expr,
	type:       ba.IR_Type,
	span:       ba.Source_Span,
}

IR_BinOp_Kind :: enum {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Exp,
	Eq,
	Ne,
	Lt,
	Gt,
	Le,
	Ge,
	And,
	Or,
}

IR_BinOp :: struct {
	op:    IR_BinOp_Kind,
	left:  IR_Expr,
	right: IR_Expr,
	type:  ba.IR_Type,
	span:  ba.Source_Span,
}

IR_Dup :: struct {
	value: ba.Intern_ID,
	span:  ba.Source_Span,
}
IR_Drop :: struct {
	value: ba.Intern_ID,
	span:  ba.Source_Span,
}
IR_Crash :: struct {
	message: IR_Expr,
	span:    ba.Source_Span,
}

IR_I32_Load :: struct {
	base:   IR_Expr,
	offset: int,
	span:   ba.Source_Span,
}

IR_I32_Store :: struct {
	base:   IR_Expr,
	offset: int,
	value:  IR_Expr,
	span:   ba.Source_Span,
}
ir_module_destroy :: proc(mod: ^IR_Module) {
	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			delete(d.params)
			delete(d.effects)
		case ^IR_Decl_Effect:
			for op in d.operations do delete(op.params)
			delete(d.operations)
		case ^IR_Decl_Const:
		}
	}
	delete(mod.decls)
	for eff in mod.effect_defs {
		for op in eff.operations do delete(op.params)
		delete(eff.operations)
		delete(eff.type_params)
	}
	delete(mod.effect_defs)
	delete(mod.string_table)
}

