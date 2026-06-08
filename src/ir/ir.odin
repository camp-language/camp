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
	^IR_Decl_Expect,
}

IR_Decl_Expect :: struct {
	condition:  IR_Expr,
	message_id: ba.Intern_ID,
	span:       ba.Source_Span,
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
	id:    ba.Intern_ID,
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
	eq_func:          ba.Canonical_Name,
	debug_func:       ba.Canonical_Name,
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
	rest:    ba.Intern_ID,
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
	fn_name:             ba.Canonical_Name,
	params:              [dynamic]IR_Param,
	env:                 IR_Expr,
	body:                IR_Expr,
	type:                ba.IR_Type,
	return_type:         ba.IR_Type,
	span:                ba.Source_Span,
	is_self_referential: bool, // true when the closure references its own binding name
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
	Shl,
	Shr,
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
ir_expr_destroy :: proc(e: IR_Expr, freed: ^map[rawptr]bool) {
	if e == nil do return
	#partial switch v in e {
	case ^IR_Literal_Int:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Literal_Float:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Literal_String:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Literal_Bool:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Var:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Let:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.value, freed)
		ir_expr_destroy(v.body, freed)
		free(v)
	case ^IR_Call:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for arg in v.args do ir_expr_destroy(arg, freed)
		delete(v.args)
		free(v)
	case ^IR_Tail_Call:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for arg in v.args do ir_expr_destroy(arg, freed)
		delete(v.args)
		free(v)
	case ^IR_If:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.condition, freed)
		ir_expr_destroy(v.then_branch, freed)
		ir_expr_destroy(v.else_branch, freed)
		free(v)
	case ^IR_Match:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.scrutinee, freed)
		for arm in v.arms {
			ir_pattern_destroy(arm.pattern, freed)
			ir_expr_destroy(arm.guard, freed)
			ir_expr_destroy(arm.body, freed)
		}
		delete(v.arms)
		free(v)
	case ^IR_Construct_Tag:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for arg in v.payload do ir_expr_destroy(arg, freed)
		delete(v.payload)
		free(v)
	case ^IR_Expr_Nominal_Construct:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for arg in v.payload do ir_expr_destroy(arg, freed)
		delete(v.payload)
		free(v)
	case ^IR_Construct_Record:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for f in v.fields do ir_expr_destroy(f.value, freed)
		delete(v.fields)
		ir_expr_destroy(v.rest, freed)
		free(v)
	case ^IR_Construct_Tuple:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for el in v.elements do ir_expr_destroy(el, freed)
		delete(v.elements)
		free(v)
	case ^IR_Field_Access:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.record, freed)
		free(v)
	case ^IR_Method_Call:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.receiver, freed)
		for arg in v.args do ir_expr_destroy(arg, freed)
		delete(v.args)
		free(v)
	case ^IR_Handle:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.body, freed)
		delete(v.effects)
		for arm in v.arms {
			delete(arm.params)
			ir_expr_destroy(arm.body, freed)
		}
		delete(v.arms)
		free(v)
	case ^IR_Perform:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for arg in v.args do ir_expr_destroy(arg, freed)
		delete(v.args)
		free(v)
	case ^IR_Resume:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.value, freed)
		ir_expr_destroy(v.ev, freed)
		free(v)
	case ^IR_Closure:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.env, freed)
		ir_expr_destroy(v.body, freed)
		delete(v.params)
		free(v)
	case ^IR_Closure_Call:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.callee, freed)
		for arg in v.args do ir_expr_destroy(arg, freed)
		delete(v.args)
		free(v)
	case ^IR_Return:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.value, freed)
		free(v)
	case ^IR_Block:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		for stmt in v.statements do ir_expr_destroy(stmt, freed)
		delete(v.statements)
		free(v)
	case ^IR_BinOp:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.left, freed)
		ir_expr_destroy(v.right, freed)
		free(v)
	case ^IR_Dup:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Drop:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Crash:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.message, freed)
		free(v)
	case ^IR_I32_Load:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.base, freed)
		free(v)
	case ^IR_I32_Store:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.base, freed)
		ir_expr_destroy(v.value, freed)
		free(v)
	case ^IR_Atomic_Load:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.base, freed)
		free(v)
	case ^IR_Atomic_Store:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.base, freed)
		ir_expr_destroy(v.value, freed)
		free(v)
	case ^IR_Atomic_RMW:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.base, freed)
		ir_expr_destroy(v.value, freed)
		free(v)
	case ^IR_Atomic_Fence:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Wait:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.base, freed)
		ir_expr_destroy(v.expected, freed)
		ir_expr_destroy(v.timeout, freed)
		free(v)
	case ^IR_Notify:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.base, freed)
		ir_expr_destroy(v.count, freed)
		free(v)
	case ^IR_Assign:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.value, freed)
		free(v)
	case ^IR_Loop:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		ir_expr_destroy(v.iterable, freed)
		ir_expr_destroy(v.body, freed)
		free(v)
	}
}

ir_pattern_destroy :: proc(p: IR_Pattern, freed: ^map[rawptr]bool) {
	if p == nil do return
	#partial switch v in p {
	case ^IR_Pat_Tag:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		delete(v.payload)
		free(v)
	case ^IR_Pat_Record:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		delete(v.fields)
		free(v)
	case ^IR_Pat_Var:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Pat_Wildcard:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Pat_Bool:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Pat_Int:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Pat_String:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		free(v)
	case ^IR_Pat_Tuple:
		ptr := rawptr(v)
		if ptr in freed do return
		freed[ptr] = true
		delete(v.elements)
		free(v)
	}
}

ir_module_destroy :: proc(mod: ^IR_Module, freed: ^map[rawptr]bool) {
	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			ptr := rawptr(d)
			if ptr in freed do continue
			freed[ptr] = true
			ir_expr_destroy(d.body, freed)
			delete(d.params)
			delete(d.effects)
			free(d)
		case ^IR_Decl_Effect:
			ptr := rawptr(d)
			if ptr in freed do continue
			freed[ptr] = true
			for op in d.operations do delete(op.params)
			delete(d.operations)
			free(d)
		case ^IR_Decl_Expect:
			ptr := rawptr(d)
			if ptr in freed do continue
			freed[ptr] = true
			ir_expr_destroy(d.condition, freed)
			free(d)
		case ^IR_Decl_Const:
			ptr := rawptr(d)
			if ptr in freed do continue
			freed[ptr] = true
			ir_expr_destroy(d.value, freed)
			free(d)
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

