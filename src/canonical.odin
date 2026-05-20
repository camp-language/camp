package camp

NO_NAME :: Intern_ID(-1)

// Span_Table holds source spans for canonical nodes off-tree.
// Keeping spans out of the struct itself means whitespace/comment-only edits
// produce a byte-identical canonical IR, enabling early cutoff in the
// incremental query layer.
Span_Table :: map[rawptr]Source_Span

span_set :: proc(t: Span_Table, node: rawptr, span: Source_Span) {
	t := t
	t[node] = span
}

span_of :: proc(t: Span_Table, node: rawptr) -> Source_Span {
	if span, ok := t[node]; ok {
		return span
	}
	return Source_Span_ZERO
}

Canonical_Name :: struct {
	module:   Intern_ID,
	name:     Intern_ID,
	is_local: bool,
}

Deferred_Import :: struct {
	module:    Intern_ID,
	exposing:  [dynamic]Intern_ID,
	alias:     Intern_ID,
	is_unsafe: bool,
	span:      Source_Span,
}

CDecl :: union {
	^CDecl_Const,
	^CDecl_Effect,
	^CDecl_Trait,
	^CDecl_Alias,
	^CDecl_Import,
	^CDecl_Test,
	^CDecl_Expect,
}

CDecl_Const :: struct {
	name:            Canonical_Name,
	is_pub:          bool,
	is_effectful:    bool,
	type_ann:        ^CType,
	body:            CExpr,
	derive_targets:  [dynamic]Intern_ID,
}

CDecl_Effect :: struct {
	name:       Canonical_Name,
	is_pub:     bool,
	operations: [dynamic]CEffect_Op,
}

CEffect_Op :: struct {
	name:           Intern_ID,
	is_effectful:   bool,
	params:         [dynamic]CFunc_Param,
	return_type:    ^CType,
	return_effects: ^CType,
	span:           Source_Span,
}

CDecl_Trait :: struct {
	name:    Canonical_Name,
	is_pub:  bool,
	parent:  Intern_ID,
	methods: [dynamic]CTrait_Method,
}

CTrait_Method :: struct {
	name:        Intern_ID,
	params:      [dynamic]CFunc_Param,
	return_type: ^CType,
	span:        Source_Span,
}

CDecl_Alias :: struct {
	name:   Canonical_Name,
	is_pub: bool,
	target: ^CType,
}

CDecl_Import :: struct {
	deferred: Deferred_Import,
}

CDecl_Test :: struct {
	name: string,
	body: CExpr,
}

CDecl_Expect :: struct {
	condition: CExpr,
}

CExpr :: union {
	^CExpr_Int,
	^CExpr_Float,
	^CExpr_String,
	^CExpr_Bool,
	^CExpr_Tag,
	^CExpr_Record,
	^CExpr_List,
	^CExpr_Name,
	^CExpr_Call,
	^CExpr_Method_Call,
	^CExpr_Lambda,
	^CExpr_Block,
	^CExpr_If,
	^CExpr_Match,
	^CExpr_BinOp,
	^CExpr_PrefixOp,
	^CExpr_Field_Access,
	^CExpr_Record_Update,
	^CExpr_Assign,
	^CExpr_Return,
	^CExpr_Crash,
	^CExpr_Interpolate,
	^CExpr_Handle,
}

CExpr_Int :: struct {
	value: i64,
}

CExpr_Float :: struct {
	value: f64,
}

CExpr_String :: struct {
	value: string,
}

CExpr_Bool :: struct {
	value: bool,
}

CExpr_Tag :: struct {
	name:    Canonical_Name,
	payload: [dynamic]CExpr,
}

CExpr_Record :: struct {
	fields:  [dynamic]CRecord_Field,
	rest:    CExpr,
	is_open: bool,
}

CRecord_Field :: struct {
	name:  Intern_ID,
	value: CExpr,
	span:  Source_Span,
}

CExpr_List :: struct {
	elements: [dynamic]CExpr,
}

CExpr_Name :: struct {
	name: Canonical_Name,
}

CExpr_Call :: struct {
	callee: CExpr,
	args:   [dynamic]CExpr,
}

CExpr_Method_Call :: struct {
	receiver: CExpr,
	method:   Canonical_Name,
	args:     [dynamic]CExpr,
}

CExpr_Lambda :: struct {
	type_params: [dynamic]Intern_ID,
	params:      [dynamic]CFunc_Param,
	return_type: ^CType,
	effects:     ^CType,
	body:        CExpr,
}

CFunc_Param :: struct {
	name:     Intern_ID,
	type_ann: ^CType,
	span:     Source_Span,
}

CExpr_Block :: struct {
	statements: [dynamic]CExpr,
}

CExpr_If :: struct {
	condition:   CExpr,
	then_branch: CExpr,
	else_branch: CExpr,
}

CExpr_Match :: struct {
	scrutinee: CExpr,
	arms:      [dynamic]CMatch_Arm,
}

CExpr_BinOp :: struct {
	op:    Token_Kind,
	left:  CExpr,
	right: CExpr,
}

CExpr_PrefixOp :: struct {
	op:      Token_Kind,
	operand: CExpr,
}

CExpr_Field_Access :: struct {
	record: CExpr,
	field:  Intern_ID,
}

CExpr_Record_Update :: struct {
	rest:    CExpr,
	updates: [dynamic]CRecord_Field,
}

CExpr_Assign :: struct {
	target: CExpr,
	value:  CExpr,
}

CExpr_Return :: struct {
	value: CExpr,
}

CExpr_Crash :: struct {
	message: CExpr,
}

CExpr_Interpolate :: struct {
	parts: [dynamic]CExpr,
}

CExpr_Handle :: struct {
	effect:     Canonical_Name,
	is_shallow: bool,
	body:       CExpr,
	arms:       [dynamic]CHandler_Arm,
}

CHandler_Arm :: struct {
	op:        Intern_ID,
	resume_id: Intern_ID,
	body:      CExpr,
	span:      Source_Span,
}

CMatch_Arm :: struct {
	pattern: CPattern,
	body:    CExpr,
	span:    Source_Span,
}

CPattern :: union {
	^CPattern_Tag,
	^CPattern_Record,
	^CPattern_List,
	^CPattern_Int,
	^CPattern_String,
	^CPattern_Bool,
	^CPattern_Identifier,
	^CPattern_Wildcard,
	^CPattern_Destructure,
}

CPattern_Tag :: struct {
	name:    Canonical_Name,
	payload: [dynamic]CPattern,
}

CPattern_Record :: struct {
	fields:  [dynamic]CPattern_Field,
	is_open: bool,
}

CPattern_Field :: struct {
	name:    Intern_ID,
	binding: Intern_ID,
}

CPattern_List :: struct {
	elements: [dynamic]CPattern,
}

CPattern_Int :: struct {
	value: i64,
}

CPattern_String :: struct {
	value: string,
}

CPattern_Bool :: struct {
	value: bool,
}

CPattern_Identifier :: struct {
	name: Intern_ID,
}

CPattern_Wildcard :: struct {
}

CPattern_Destructure :: struct {
	type_name: Canonical_Name,
	inner:     CPattern,
}

CType :: union {
	^CType_Primitive,
	^CType_Applied,
	^CType_Function,
	^CType_Record,
	^CType_Tag_Union,
	^CType_Effect_Row,
	^CType_Variable,
	^CType_Wildcard,
}

CType_Primitive :: struct {
	name: Intern_ID,
}

CType_Applied :: struct {
	name: Intern_ID,
	args: [dynamic]CType,
}

CType_Function :: struct {
	params:  [dynamic]CType,
	effects: ^CType,
	return_: CType,
}

CType_Record :: struct {
	fields:  [dynamic]CType_Field,
	rest:    Intern_ID,
	is_open: bool,
}

CType_Field :: struct {
	name: Intern_ID,
	type: CType,
}

CType_Tag_Union :: struct {
	tags:    [dynamic]CType_Tag,
	rest:    Intern_ID,
	is_open: bool,
}

CType_Tag :: struct {
	name:    Intern_ID,
	payload: [dynamic]CType,
}

CType_Effect_Row :: struct {
	effects: [dynamic]Intern_ID,
	rest:    Intern_ID,
	is_open: bool,
}

CType_Variable :: struct {
	name: Intern_ID,
}

CType_Wildcard :: struct {
}

CFile :: struct {
	path:    string,
	decls:   [dynamic]CDecl,
	imports: [dynamic]Deferred_Import,
	span:    Source_Span,
	spans:   Span_Table,
}
