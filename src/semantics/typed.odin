package semantics

import "camp:base"
import "camp:frontend"

Type_ID :: base.Type_Var_ID

TExpr :: union {
	^TExpr_Int,
	^TExpr_Float,
	^TExpr_String,
	^TExpr_Bool,
	^TExpr_Char,
	^TExpr_Todo,
	^TExpr_Tag,
	^TExpr_Nominal_Construct,
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
	^TExpr_Interpolated_String,
	^TExpr_Handle,
	^TExpr_Perform,
	^TExpr_For,
	^TExpr_Par,
}

TExpr_Int :: struct {
	value:  i64,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_Float :: struct {
	value:  f64,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_String :: struct {
	value:  string,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_Bool :: struct {
	value:  bool,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_Char :: struct {
	value: u8,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_Tag :: struct {
	name:    base.Canonical_Name,
	payload: [dynamic]TExpr,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
}

TExpr_Nominal_Construct :: struct {
	type_name: base.Canonical_Name,
	variant:   base.Intern_ID,
	payload:   [dynamic]TExpr,
	resolved_type: Type_ID,
	span:      base.Source_Span,
}

TExpr_Record :: struct {
	fields:  [dynamic]TRecord_Field,
	rest:    TExpr,
	is_open: bool,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
}

TRecord_Field :: struct {
	name:  base.Intern_ID,
	value: TExpr,
	span:  base.Source_Span,
}

TExpr_List :: struct {
	elements: [dynamic]TExpr,
	rest:     TExpr,
	type_:    base.IR_Type,
	eff_:     base.IR_Type,
	span:     base.Source_Span,
}

TExpr_Name :: struct {
	name:  base.Canonical_Name,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_Call :: struct {
	callee: TExpr,
	args:   [dynamic]TExpr,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_Method_Call :: struct {
	receiver:  TExpr,
	method:    base.Canonical_Name,
	args:      [dynamic]TExpr,
	type_:     base.IR_Type,
	eff_:      base.IR_Type,
	resolved_: base.Canonical_Name,
	dispatch:  frontend.Dispatch_Kind,
	span:      base.Source_Span,
}

TExpr_Lambda :: struct {
	type_params: [dynamic]frontend.Type_Param,
	params:      [dynamic]TFunc_Param,
	return_type: base.IR_Type,
	effects:     base.IR_Type,
	body:        TExpr,
	type_:       base.IR_Type,
	eff_:        base.IR_Type,
	span:        base.Source_Span,
}

TFunc_Param :: struct {
	name:     base.Intern_ID,
	type_:    base.IR_Type,
	eff_:     base.IR_Type,
	span:     base.Source_Span,
}

TExpr_Block :: struct {
	statements: [dynamic]TExpr,
	type_:      base.IR_Type,
	eff_:       base.IR_Type,
	span:       base.Source_Span,
}

TExpr_If :: struct {
	condition:   TExpr,
	then_branch: TExpr,
	else_branch: TExpr,
	type_:       base.IR_Type,
	eff_:        base.IR_Type,
	span:        base.Source_Span,
}

TExpr_Match :: struct {
	scrutinee: TExpr,
	arms:      [dynamic]TMatch_Arm,
	type_:     base.IR_Type,
	eff_:      base.IR_Type,
	span:       base.Source_Span,
}

TMatch_Arm :: struct {
	pattern: TPattern,
	body:    TExpr,
	span:    base.Source_Span,
}

TPattern :: union {
	^TPattern_Tag,
	^TPattern_Record,
	^TPattern_List,
	^TPattern_Int,
	^TPattern_String,
	^TPattern_Bool,
	^TPattern_Char,
	^TPattern_Identifier,
	^TPattern_Wildcard,
	^TPattern_Destructure,
	^TPattern_Or,
}

TPattern_Tag :: struct {
	name:    base.Canonical_Name,
	payload: [dynamic]TPattern,
	span:    base.Source_Span,
}

TPattern_Record :: struct {
	fields:  [dynamic]TPattern_Field,
	is_open: bool,
	span:    base.Source_Span,
}

TPattern_Field :: struct {
	name:    base.Intern_ID,
	binding: base.Intern_ID,
	span:    base.Source_Span,
}

TPattern_List :: struct {
	elements: [dynamic]TPattern,
	rest:     TPattern,
	span:     base.Source_Span,
}

TPattern_Int :: struct {
	value: i64,
	span:  base.Source_Span,
}

TPattern_String :: struct {
	value: string,
	span:  base.Source_Span,
}

TPattern_Bool :: struct {
	value: bool,
	span:  base.Source_Span,
}

TPattern_Char :: struct {
	value: u8,
	span:  base.Source_Span,
}

TPattern_Identifier :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

TPattern_Wildcard :: struct {
	span: base.Source_Span,
}

TPattern_Destructure :: struct {
	type_name: base.Canonical_Name,
	inner:     TPattern,
	span:      base.Source_Span,
}

TPattern_Or :: struct {
	alternatives: [dynamic]TPattern,
	span:         base.Source_Span,
}

TExpr_BinOp :: struct {
	op:    base.Token_Kind,
	left:  TExpr,
	right: TExpr,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_PrefixOp :: struct {
	op:     base.Token_Kind,
	operand: TExpr,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_Field_Access :: struct {
	record:  TExpr,
	field:   base.Intern_ID,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
}

TExpr_Record_Update :: struct {
	rest:     TExpr,
	updates:  [dynamic]TRecord_Field,
	type_:    base.IR_Type,
	eff_:     base.IR_Type,
	span:     base.Source_Span,
}

TExpr_Assign :: struct {
	target: TExpr,
	value:  TExpr,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_Return :: struct {
	value: TExpr,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_Crash :: struct {
	message: TExpr,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
}

TExpr_Todo :: struct {
	message: TExpr,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
}

TExpr_Interpolated_String :: struct {
	parts: [dynamic]TExpr_String_Part,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_String_Part :: union {
	^TExpr_String_Literal,
	^TExpr_String_Expr,
}

TExpr_String_Literal :: struct {
	value: string,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_String_Expr :: struct {
	expr:          TExpr,
	needs_to_str:  bool,
	display_impl:  base.Canonical_Name,
}

TExpr_Handle :: struct {
	effects: [dynamic]base.Canonical_Name,
	body:   TExpr,
	arms:   [dynamic]THandler_Arm,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_Perform :: struct {
	effect: base.Canonical_Name,
	op:     base.Intern_ID,
	args:   [dynamic]TExpr,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}

TExpr_For :: struct {
	var:      base.Intern_ID,
	iterable: TExpr,
	body:     TExpr,
	type_:    base.IR_Type,
	eff_:     base.IR_Type,
	span:     base.Source_Span,
}

TExpr_Par :: struct {
	names:       [dynamic]base.Intern_ID, // field names for par { name: expr, ... }
	expressions: [dynamic]TExpr,
	for_var:     base.Intern_ID,
	for_iter:    TExpr,
	for_body:    TExpr,
	type_:       base.IR_Type,
	eff_:        base.IR_Type,
	span:        base.Source_Span,
}

THandler_Arm :: struct {
	op:     base.Intern_ID,
	params: [dynamic]base.Intern_ID,
	body:   TExpr,
	span:   base.Source_Span,
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
	^TDecl_Is_Impl,
}

TDecl_Const :: struct {
	name:            base.Canonical_Name,
	is_pub:          bool,
	is_effectful:    bool,
	type_ann:        ^CType,
	body:            TExpr,
	type_:           base.IR_Type,
	eff_:            base.IR_Type,
	derive_targets:  [dynamic]base.Intern_ID,
	span:            base.Source_Span,
}

TDecl_Effect :: struct {
	name:       base.Canonical_Name,
	is_pub:     bool,
	operations: [dynamic]TEffect_Op,
	type_params: [dynamic]frontend.Type_Param,
	span:       base.Source_Span,
}

TEffect_Op :: struct {
	name:           base.Intern_ID,
	is_effectful:   bool,
	params:         [dynamic]TFunc_Param,
	return_type:    base.IR_Type,
	return_effects: base.IR_Type,
	span:           base.Source_Span,
}

TDecl_Trait :: struct {
	name:    base.Canonical_Name,
	is_pub:  bool,
	parent:  base.Intern_ID,
	methods: [dynamic]TTrait_Method,
	span:    base.Source_Span,
}

TTrait_Method :: struct {
	name:        base.Intern_ID,
	params:      [dynamic]TFunc_Param,
	return_type: base.IR_Type,
	effects:     base.IR_Type,
	span:        base.Source_Span,
}

TDecl_Alias :: struct {
	name:   base.Canonical_Name,
	is_pub: bool,
	target: ^CType,
	span:   base.Source_Span,
}

TDecl_Newtype :: struct {
	name:           base.Canonical_Name,
	is_pub:         bool,
	type_params:    [dynamic]base.Intern_ID,
	inner_type:     ^CType,
	type_:          base.IR_Type,
	derive_targets: [dynamic]base.Intern_ID,
	span:           base.Source_Span,
}

TDecl_Import :: struct {
	deferred: base.Deferred_Import,
	span:     base.Source_Span,
}

TDecl_Test :: struct {
	name: string,
	body: TExpr,
	span: base.Source_Span,
}

TDecl_Expect :: struct {
	condition: TExpr,
	span:      base.Source_Span,
}

TDecl_Is_Impl :: struct {
	type_name:  base.Canonical_Name,
	trait_name: base.Canonical_Name,
	methods:    [dynamic]TIs_Method,
	span:       base.Source_Span,
}

TIs_Method :: struct {
	name:    base.Intern_ID,
	params:  [dynamic]TFunc_Param,
	body:    TExpr,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	is_pub:  bool,
	span:    base.Source_Span,
}

TFile :: struct {
	path:    string,
	decls:   [dynamic]TDecl,
	imports: [dynamic]base.Deferred_Import,
	span:    base.Source_Span,
}