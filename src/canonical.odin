package camp

NO_NAME :: Intern_ID(-1)

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
	^CDecl_Newtype,
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
	span:            Source_Span,
}

CDecl_Effect :: struct {
	name:       Canonical_Name,
	is_pub:     bool,
	operations: [dynamic]CEffect_Op,
	type_params: [dynamic]Type_Param,
	span:       Source_Span,
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
	span:    Source_Span,
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
	span:   Source_Span,
}

CDecl_Newtype :: struct {
	name:           Canonical_Name,
	is_pub:         bool,
	pub_variants:   bool,
	type_params:    [dynamic]Intern_ID,
	trait_conforms: [dynamic]Intern_ID,
	inner_type:     ^CType,
	derive_targets: [dynamic]Intern_ID,
	span:           Source_Span,
}

CDecl_Import :: struct {
	deferred: Deferred_Import,
	span:     Source_Span,
}

CDecl_Test :: struct {
	name: string,
	body: CExpr,
	span: Source_Span,
}

CDecl_Expect :: struct {
	condition: CExpr,
	span:      Source_Span,
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
	^CExpr_Perform,
	^CExpr_Par,
}

CExpr_Int :: struct {
	value: i64,
	span:  Source_Span,
}

CExpr_Float :: struct {
	value: f64,
	span:  Source_Span,
}

CExpr_String :: struct {
	value: string,
	span:  Source_Span,
}

CExpr_Bool :: struct {
	value: bool,
	span:  Source_Span,
}

CExpr_Tag :: struct {
	name:    Canonical_Name,
	payload: [dynamic]CExpr,
	span:    Source_Span,
}

CExpr_Record :: struct {
	fields:  [dynamic]CRecord_Field,
	rest:    CExpr,
	is_open: bool,
	span:    Source_Span,
}

CRecord_Field :: struct {
	name:  Intern_ID,
	value: CExpr,
	span:  Source_Span,
}

CExpr_List :: struct {
	elements: [dynamic]CExpr,
	span:     Source_Span,
}

CExpr_Name :: struct {
	name: Canonical_Name,
	span: Source_Span,
}

CExpr_Call :: struct {
	callee: CExpr,
	args:   [dynamic]CExpr,
	span:   Source_Span,
}

CExpr_Method_Call :: struct {
	receiver:      CExpr,
	method:        Canonical_Name,
	args:          [dynamic]CExpr,
	is_effectful:  bool,
	span:          Source_Span,
}

CExpr_Lambda :: struct {
	type_params: [dynamic]Type_Param,
	params:      [dynamic]CFunc_Param,
	return_type: ^CType,
	effects:     ^CType,
	body:        CExpr,
	span:        Source_Span,
}

CFunc_Param :: struct {
	name:     Intern_ID,
	type_ann: ^CType,
	span:     Source_Span,
}

CExpr_Block :: struct {
	statements: [dynamic]CExpr,
	span:       Source_Span,
}

CExpr_If :: struct {
	condition:   CExpr,
	then_branch: CExpr,
	else_branch: CExpr,
	span:        Source_Span,
}

CExpr_Match :: struct {
	scrutinee: CExpr,
	arms:      [dynamic]CMatch_Arm,
	span:      Source_Span,
}

CExpr_BinOp :: struct {
	op:    Token_Kind,
	left:  CExpr,
	right: CExpr,
	span:  Source_Span,
}

CExpr_PrefixOp :: struct {
	op:      Token_Kind,
	operand: CExpr,
	span:    Source_Span,
}

CExpr_Field_Access :: struct {
	record: CExpr,
	field:  Intern_ID,
	span:   Source_Span,
}

CExpr_Record_Update :: struct {
	rest:    CExpr,
	updates: [dynamic]CRecord_Field,
	span:    Source_Span,
}

CExpr_Assign :: struct {
	target: CExpr,
	value:  CExpr,
	span:   Source_Span,
}

CExpr_Return :: struct {
	value: CExpr,
	span:  Source_Span,
}

CExpr_Crash :: struct {
	message: CExpr,
	span:    Source_Span,
}

CExpr_Interpolate :: struct {
	parts: [dynamic]CExpr,
	span:  Source_Span,
}

CExpr_Handle :: struct {
	effect:     Canonical_Name,
	is_shallow: bool,
	body:       CExpr,
	arms:       [dynamic]CHandler_Arm,
	span:       Source_Span,
}

CExpr_Perform :: struct {
	effect: Canonical_Name,
	op:     Intern_ID,
	args:   [dynamic]CExpr,
	span:   Source_Span,
}

CExpr_Par :: struct {
	expressions: [dynamic]CExpr,  // for par { e1, e2 }
	for_var:     Intern_ID,      // 0 if not par-for
	for_iter:    CExpr,          // the xs in "par for x in xs"
	for_body:    CExpr,          // the body in "par for x in xs { body }"
	span:        Source_Span,
}

CHandler_Arm :: struct {
	op:     Intern_ID,
	params: [dynamic]Intern_ID,
	body:   CExpr,
	span:   Source_Span,
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
	span:    Source_Span,
}

CPattern_Record :: struct {
	fields:  [dynamic]CPattern_Field,
	is_open: bool,
	span:    Source_Span,
}

CPattern_Field :: struct {
	name:    Intern_ID,
	binding: Intern_ID,
	span:    Source_Span,
}

CPattern_List :: struct {
	elements: [dynamic]CPattern,
	span:     Source_Span,
}

CPattern_Int :: struct {
	value: i64,
	span:  Source_Span,
}

CPattern_String :: struct {
	value: string,
	span:  Source_Span,
}

CPattern_Bool :: struct {
	value: bool,
	span:  Source_Span,
}

CPattern_Identifier :: struct {
	name: Intern_ID,
	span: Source_Span,
}

CPattern_Wildcard :: struct {
	span: Source_Span,
}

CPattern_Destructure :: struct {
	type_name: Canonical_Name,
	inner:     CPattern,
	span:      Source_Span,
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
	^CType_Self,
}

CType_Primitive :: struct {
	name: Intern_ID,
	span: Source_Span,
}

CType_Applied :: struct {
	name: Intern_ID,
	args: [dynamic]CType,
	span: Source_Span,
}

CType_Function :: struct {
	params:  [dynamic]CType,
	effects: ^CType,
	return_: CType,
	span:    Source_Span,
}

CType_Record :: struct {
	fields:  [dynamic]CType_Field,
	rest:    Intern_ID,
	is_open: bool,
	span:    Source_Span,
}

CType_Field :: struct {
	name: Intern_ID,
	type: CType,
	span: Source_Span,
}

CType_Tag_Union :: struct {
	tags:    [dynamic]CType_Tag,
	rest:    Intern_ID,
	is_open: bool,
	span:    Source_Span,
}

CType_Tag :: struct {
	name:    Intern_ID,
	payload: [dynamic]CType,
	span:    Source_Span,
}

CType_Effect_Entry :: struct {
	name:      Intern_ID,
	type_args: [dynamic]CType,
	span:      Source_Span,
}

CType_Effect_Row :: struct {
	effects: [dynamic]CType_Effect_Entry,
	rest:    Intern_ID,
	is_open: bool,
	span:    Source_Span,
}

CType_Variable :: struct {
	name: Intern_ID,
	span: Source_Span,
}

CType_Wildcard :: struct {
	span: Source_Span,
}

CType_Self :: struct {
	span: Source_Span,
}

CFile :: struct {
	path:    string,
	decls:   [dynamic]CDecl,
	imports: [dynamic]Deferred_Import,
	span:    Source_Span,
}
