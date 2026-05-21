package camp

TExpr :: union {
	^TExpr_Int,
	^TExpr_Float,
	^TExpr_String,
	^TExpr_Bool,
	^TExpr_Tag,
	^TExpr_Record,
	^TExpr_List,
	^TExpr_Name,
	^TExpr_Call,
	^TExpr_Method_Call,
	^TExpr_Lambda,
	^TExpr_Block,
	^TExpr_If,
	^TExpr_Match,
	^TExpr_BinOp,
	^TExpr_PrefixOp,
	^TExpr_Field_Access,
	^TExpr_Record_Update,
	^TExpr_Assign,
	^TExpr_Return,
	^TExpr_Crash,
	^TExpr_Interpolate,
	^TExpr_Handle,
}

TExpr_Int :: struct {
	value:  i64,
	type_:  IR_Type,
	eff_:   IR_Type,
	span:   Source_Span,
}

TExpr_Float :: struct {
	value:  f64,
	type_:  IR_Type,
	eff_:   IR_Type,
	span:   Source_Span,
}

TExpr_String :: struct {
	value:  string,
	type_:  IR_Type,
	eff_:   IR_Type,
	span:   Source_Span,
}

TExpr_Bool :: struct {
	value:  bool,
	type_:  IR_Type,
	eff_:   IR_Type,
	span:   Source_Span,
}

TExpr_Tag :: struct {
	name:    Canonical_Name,
	payload: [dynamic]TExpr,
	type_:   IR_Type,
	eff_:    IR_Type,
	span:    Source_Span,
}

TExpr_Record :: struct {
	fields:  [dynamic]TRecord_Field,
	rest:    TExpr,
	is_open: bool,
	type_:   IR_Type,
	eff_:    IR_Type,
	span:    Source_Span,
}

TRecord_Field :: struct {
	name:  Intern_ID,
	value: TExpr,
	span:  Source_Span,
}

TExpr_List :: struct {
	elements: [dynamic]TExpr,
	type_:    IR_Type,
	eff_:     IR_Type,
	span:     Source_Span,
}

TExpr_Name :: struct {
	name:  Canonical_Name,
	type_: IR_Type,
	eff_:  IR_Type,
	span:  Source_Span,
}

TExpr_Call :: struct {
	callee: TExpr,
	args:   [dynamic]TExpr,
	type_:  IR_Type,
	eff_:   IR_Type,
	span:   Source_Span,
}

TExpr_Method_Call :: struct {
	receiver:  TExpr,
	method:    Canonical_Name,
	args:      [dynamic]TExpr,
	type_:     IR_Type,
	eff_:      IR_Type,
	resolved_: Canonical_Name,
	span:      Source_Span,
}

TExpr_Lambda :: struct {
	type_params: [dynamic]Type_Param,
	params:      [dynamic]TFunc_Param,
	return_type: IR_Type,
	effects:     IR_Type,
	body:        TExpr,
	type_:       IR_Type,
	eff_:        IR_Type,
	span:        Source_Span,
}

TFunc_Param :: struct {
	name:     Intern_ID,
	type_:    IR_Type,
	eff_:     IR_Type,
	span:     Source_Span,
}

TExpr_Block :: struct {
	statements: [dynamic]TExpr,
	type_:      IR_Type,
	eff_:       IR_Type,
	span:       Source_Span,
}

TExpr_If :: struct {
	condition:   TExpr,
	then_branch: TExpr,
	else_branch: TExpr,
	type_:       IR_Type,
	eff_:        IR_Type,
	span:        Source_Span,
}

TExpr_Match :: struct {
	scrutinee: TExpr,
	arms:      [dynamic]TMatch_Arm,
	type_:     IR_Type,
	eff_:      IR_Type,
	span:       Source_Span,
}

TMatch_Arm :: struct {
	pattern: TPattern,
	body:    TExpr,
	span:    Source_Span,
}

TPattern :: union {
	^TPattern_Tag,
	^TPattern_Record,
	^TPattern_List,
	^TPattern_Int,
	^TPattern_String,
	^TPattern_Bool,
	^TPattern_Identifier,
	^TPattern_Wildcard,
	^TPattern_Destructure,
}

TPattern_Tag :: struct {
	name:    Canonical_Name,
	payload: [dynamic]TPattern,
	span:    Source_Span,
}

TPattern_Record :: struct {
	fields:  [dynamic]TPattern_Field,
	is_open: bool,
	span:    Source_Span,
}

TPattern_Field :: struct {
	name:    Intern_ID,
	binding: Intern_ID,
	span:    Source_Span,
}

TPattern_List :: struct {
	elements: [dynamic]TPattern,
	span:     Source_Span,
}

TPattern_Int :: struct {
	value: i64,
	span:  Source_Span,
}

TPattern_String :: struct {
	value: string,
	span:  Source_Span,
}

TPattern_Bool :: struct {
	value: bool,
	span:  Source_Span,
}

TPattern_Identifier :: struct {
	name: Intern_ID,
	span: Source_Span,
}

TPattern_Wildcard :: struct {
	span: Source_Span,
}

TPattern_Destructure :: struct {
	type_name: Canonical_Name,
	inner:     TPattern,
	span:      Source_Span,
}

TExpr_BinOp :: struct {
	op:    Token_Kind,
	left:  TExpr,
	right: TExpr,
	type_: IR_Type,
	eff_:  IR_Type,
	span:  Source_Span,
}

TExpr_PrefixOp :: struct {
	op:     Token_Kind,
	operand: TExpr,
	type_:  IR_Type,
	eff_:   IR_Type,
	span:   Source_Span,
}

TExpr_Field_Access :: struct {
	record:  TExpr,
	field:   Intern_ID,
	type_:   IR_Type,
	eff_:    IR_Type,
	span:    Source_Span,
}

TExpr_Record_Update :: struct {
	rest:     TExpr,
	updates:  [dynamic]TRecord_Field,
	type_:    IR_Type,
	eff_:     IR_Type,
	span:     Source_Span,
}

TExpr_Assign :: struct {
	target: TExpr,
	value:  TExpr,
	type_:  IR_Type,
	eff_:   IR_Type,
	span:   Source_Span,
}

TExpr_Return :: struct {
	value: TExpr,
	type_: IR_Type,
	eff_:  IR_Type,
	span:  Source_Span,
}

TExpr_Crash :: struct {
	message: TExpr,
	type_:   IR_Type,
	eff_:    IR_Type,
	span:    Source_Span,
}

TExpr_Interpolate :: struct {
	parts: [dynamic]TExpr,
	type_: IR_Type,
	eff_:  IR_Type,
	span:  Source_Span,
}

TExpr_Handle :: struct {
	effect:     Canonical_Name,
	is_shallow: bool,
	body:       TExpr,
	arms:       [dynamic]THandler_Arm,
	type_:      IR_Type,
	eff_:       IR_Type,
	span:       Source_Span,
}

THandler_Arm :: struct {
	op:        Intern_ID,
	resume_id: Intern_ID,
	body:      TExpr,
	span:      Source_Span,
}

TDecl :: union {
	^TDecl_Const,
	^TDecl_Effect,
	^TDecl_Trait,
	^TDecl_Alias,
	^TDecl_Newtype,
	^TDecl_Import,
	^TDecl_Test,
	^TDecl_Expect,
}

TDecl_Const :: struct {
	name:            Canonical_Name,
	is_pub:          bool,
	is_effectful:    bool,
	type_ann:        ^CType,
	body:            TExpr,
	type_:           IR_Type,
	eff_:            IR_Type,
	derive_targets:  [dynamic]Intern_ID,
	span:            Source_Span,
}

TDecl_Effect :: struct {
	name:       Canonical_Name,
	is_pub:     bool,
	operations: [dynamic]TEffect_Op,
	span:       Source_Span,
}

TEffect_Op :: struct {
	name:           Intern_ID,
	is_effectful:   bool,
	params:         [dynamic]TFunc_Param,
	return_type:    IR_Type,
	return_effects: IR_Type,
	span:           Source_Span,
}

TDecl_Trait :: struct {
	name:    Canonical_Name,
	is_pub:  bool,
	parent:  Intern_ID,
	methods: [dynamic]TTrait_Method,
	span:    Source_Span,
}

TTrait_Method :: struct {
	name:        Intern_ID,
	params:      [dynamic]TFunc_Param,
	return_type: IR_Type,
	effects:     IR_Type,
	span:        Source_Span,
}

TDecl_Alias :: struct {
	name:   Canonical_Name,
	is_pub: bool,
	target: ^CType,
	span:   Source_Span,
}

TDecl_Newtype :: struct {
	name:           Canonical_Name,
	is_pub:         bool,
	type_params:    [dynamic]Intern_ID,
	trait_conforms: [dynamic]Intern_ID,
	inner_type:     ^CType,
	type_:          IR_Type,
	derive_targets: [dynamic]Intern_ID,
	span:           Source_Span,
}

TDecl_Import :: struct {
	deferred: Deferred_Import,
	span:     Source_Span,
}

TDecl_Test :: struct {
	name: string,
	body: TExpr,
	span: Source_Span,
}

TDecl_Expect :: struct {
	condition: TExpr,
	span:      Source_Span,
}

TFile :: struct {
	path:    string,
	decls:   [dynamic]TDecl,
	imports: [dynamic]Deferred_Import,
	span:    Source_Span,
}