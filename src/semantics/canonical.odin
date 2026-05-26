package semantics

import "camp:base"
import "camp:frontend"

CDecl :: union {
	^CDecl_Const,
	^CDecl_Effect,
	^CDecl_Trait,
	^CDecl_Is_Impl,
	^CDecl_Alias,
	^CDecl_Newtype,
	^CDecl_Import,
	^CDecl_Test,
	^CDecl_Expect,
}

CDecl_Const :: struct {
	name:           base.Canonical_Name,
	is_pub:         bool,
	is_effectful:   bool,
	type_ann:       ^CType,
	body:           CExpr,
	derive_targets: [dynamic]base.Intern_ID,
	where_clauses:  [dynamic]frontend.Where_Clause,
	span:           base.Source_Span,
}

CDecl_Effect :: struct {
	name:        base.Canonical_Name,
	is_pub:      bool,
	operations:  [dynamic]CEffect_Op,
	type_params: [dynamic]frontend.Type_Param,
	span:        base.Source_Span,
}

CEffect_Op :: struct {
	name:           base.Intern_ID,
	is_effectful:   bool,
	params:         [dynamic]CFunc_Param,
	return_type:    ^CType,
	return_effects: ^CType,
	span:           base.Source_Span,
}

CDecl_Trait :: struct {
	name:    base.Canonical_Name,
	is_pub:  bool,
	parent:  base.Intern_ID,
	methods: [dynamic]CTrait_Method,
	span:    base.Source_Span,
}

CTrait_Method :: struct {
	name:        base.Intern_ID,
	params:      [dynamic]CFunc_Param,
	return_type: ^CType,
	span:        base.Source_Span,
}

CDecl_Alias :: struct {
	name:   base.Canonical_Name,
	is_pub: bool,
	target: ^CType,
	span:   base.Source_Span,
}

CDecl_Newtype :: struct {
	name:           base.Canonical_Name,
	is_pub:         bool,
	pub_variants:   bool,
	type_params:    [dynamic]base.Intern_ID,
	inner_type:     ^CType,
	derive_targets: [dynamic]base.Intern_ID,
	span:           base.Source_Span,
}

CDecl_Import :: struct {
	deferred: base.Deferred_Import,
	span:     base.Source_Span,
}

CDecl_Test :: struct {
	name: string,
	body: CExpr,
	span: base.Source_Span,
}

CDecl_Expect :: struct {
	condition: CExpr,
	span:      base.Source_Span,
}

CDecl_Is_Impl :: struct {
	type_name:  base.Canonical_Name,
	trait_name: base.Canonical_Name,
	methods:    [dynamic]CIs_Method,
	span:       base.Source_Span,
}

CIs_Method :: struct {
	name: base.Intern_ID,
	body: CExpr,
	span: base.Source_Span,
}

CExpr :: union {
	^CExpr_Int,
	^CExpr_Float,
	^CExpr_String,
	^CExpr_Bool,
	^CExpr_Char,
	^CExpr_Tag,
	^CExpr_Nominal_Construct,
	^CExpr_Record,
	^CExpr_Tuple,
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
	^CExpr_Field_Index,
	^CExpr_Record_Update,
	^CExpr_Assign,
	^CExpr_Return,
	^CExpr_Crash,
	^CExpr_Todo,
	^CExpr_Interpolated_String,
	^CExpr_Handle,
	^CExpr_Perform,
	^CExpr_Par,
	^CExpr_For,
}

CExpr_Int :: struct {
	value: i64,
	span:  base.Source_Span,
}

CExpr_Float :: struct {
	value: f64,
	span:  base.Source_Span,
}

CExpr_String :: struct {
	value: string,
	span:  base.Source_Span,
}

CExpr_Bool :: struct {
	value: bool,
	span:  base.Source_Span,
}

CExpr_Char :: struct {
	value: u8,
	span:  base.Source_Span,
}

CExpr_Tag :: struct {
	name:    base.Canonical_Name,
	payload: [dynamic]CExpr,
	span:    base.Source_Span,
}

CExpr_Nominal_Construct :: struct {
	type_name: base.Canonical_Name,
	variant:   base.Intern_ID, // 0 = simple wrap, non-zero = qualified variant
	payload:   [dynamic]CExpr,
	span:      base.Source_Span,
}

CExpr_Record :: struct {
	fields:  [dynamic]CRecord_Field,
	rest:    CExpr,
	is_open: bool,
	span:    base.Source_Span,
}
CExpr_Tuple :: struct {
	elements: [dynamic]CExpr,
	span:     base.Source_Span,
}

CRecord_Field :: struct {
	name:  base.Intern_ID,
	value: CExpr,
	span:  base.Source_Span,
}

CExpr_List :: struct {
	elements: [dynamic]CExpr,
	rest:     CExpr,
	span:     base.Source_Span,
}

CExpr_Name :: struct {
	name: base.Canonical_Name,
	span: base.Source_Span,
}

CExpr_Call :: struct {
	callee: CExpr,
	args:   [dynamic]CExpr,
	span:   base.Source_Span,
}

CExpr_Method_Call :: struct {
	receiver:     CExpr,
	method:       base.Canonical_Name,
	args:         [dynamic]CExpr,
	is_effectful: bool,
	dispatch:     frontend.Dispatch_Kind,
	span:         base.Source_Span,
}

CExpr_Lambda :: struct {
	type_params:   [dynamic]frontend.Type_Param,
	params:        [dynamic]CFunc_Param,
	return_type:   ^CType,
	effects:       ^CType,
	where_clauses: [dynamic]frontend.Where_Clause,
	body:          CExpr,
	span:          base.Source_Span,
}

CFunc_Param :: struct {
	name:     base.Intern_ID,
	type_ann: ^CType,
	span:     base.Source_Span,
}

CExpr_Block :: struct {
	statements: [dynamic]CExpr,
	span:       base.Source_Span,
}

CExpr_If :: struct {
	condition:   CExpr,
	then_branch: CExpr,
	else_branch: CExpr,
	span:        base.Source_Span,
}

CExpr_Match :: struct {
	scrutinee: CExpr,
	arms:      [dynamic]CMatch_Arm,
	span:      base.Source_Span,
}

CExpr_BinOp :: struct {
	op:    base.Token_Kind,
	left:  CExpr,
	right: CExpr,
	span:  base.Source_Span,
}

CExpr_PrefixOp :: struct {
	op:      base.Token_Kind,
	operand: CExpr,
	span:    base.Source_Span,
}

CExpr_Field_Access :: struct {
	record: CExpr,
	field:  base.Intern_ID,
	span:   base.Source_Span,
}
CExpr_Field_Index :: struct {
	record:      CExpr,
	field_index: int,
	span:        base.Source_Span,
}

CExpr_Record_Update :: struct {
	rest:    CExpr,
	updates: [dynamic]CRecord_Field,
	span:    base.Source_Span,
}

CExpr_Assign :: struct {
	target:   CExpr,
	value:    CExpr,
	type_ann: ^CType,
	span:     base.Source_Span,
}

CExpr_Return :: struct {
	value: CExpr,
	span:  base.Source_Span,
}

CExpr_Crash :: struct {
	message: CExpr,
	span:    base.Source_Span,
}

CExpr_Todo :: struct {
	message: CExpr,
	span:    base.Source_Span,
}

CExpr_Interpolated_String :: struct {
	parts: [dynamic]CExpr_String_Part,
	span:  base.Source_Span,
}

CExpr_String_Part :: union {
	^CExpr_String_Literal,
	CExpr,
}

CExpr_String_Literal :: struct {
	value: string,
	span:  base.Source_Span,
}

CExpr_Handle :: struct {
	effects: [dynamic]base.Canonical_Name,
	body:    CExpr,
	arms:    [dynamic]CHandler_Arm,
	span:    base.Source_Span,
}

CExpr_Perform :: struct {
	effect: base.Canonical_Name,
	op:     base.Intern_ID,
	args:   [dynamic]CExpr,
	span:   base.Source_Span,
}

CExpr_For :: struct {
	var:      base.Intern_ID,
	iterable: CExpr,
	body:     CExpr,
	span:     base.Source_Span,
}

CExpr_Par :: struct {
	names:       [dynamic]base.Intern_ID, // field names for par { name: expr, ... }
	expressions: [dynamic]CExpr, // for par { e1, e2 }
	for_var:     base.Intern_ID, // 0 if not par-for
	for_iter:    CExpr, // the xs in "par for x in xs"
	for_body:    CExpr, // the body in "par for x in xs { body }"
	span:        base.Source_Span,
}

CHandler_Arm :: struct {
	op:     base.Intern_ID,
	params: [dynamic]base.Intern_ID,
	body:   CExpr,
	span:   base.Source_Span,
}

CMatch_Arm :: struct {
	pattern: CPattern,
	guard:   CExpr,
	body:    CExpr,
	span:    base.Source_Span,
}

CPattern :: union {
	^CPattern_Tag,
	^CPattern_Record,
	^CPattern_Tuple,
	^CPattern_List,
	^CPattern_Int,
	^CPattern_String,
	^CPattern_Bool,
	^CPattern_Char,
	^CPattern_Identifier,
	^CPattern_Wildcard,
	^CPattern_Destructure,
	^CPattern_Or,
}

CPattern_Tag :: struct {
	name:    base.Canonical_Name,
	payload: [dynamic]CPattern,
	span:    base.Source_Span,
}

CPattern_Record :: struct {
	fields:  [dynamic]CPattern_Field,
	is_open: bool,
	span:    base.Source_Span,
}
CPattern_Tuple :: struct {
	elements: [dynamic]CPattern,
	span:     base.Source_Span,
}

CPattern_Field :: struct {
	name:    base.Intern_ID,
	binding: base.Intern_ID,
	span:    base.Source_Span,
}

CPattern_List :: struct {
	elements: [dynamic]CPattern,
	rest:     CPattern,
	span:     base.Source_Span,
}

CPattern_Int :: struct {
	value: i64,
	span:  base.Source_Span,
}

CPattern_String :: struct {
	value: string,
	span:  base.Source_Span,
}

CPattern_Bool :: struct {
	value: bool,
	span:  base.Source_Span,
}

CPattern_Char :: struct {
	value: u8,
	span:  base.Source_Span,
}

CPattern_Identifier :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

CPattern_Wildcard :: struct {
	span: base.Source_Span,
}

CPattern_Destructure :: struct {
	type_name: base.Canonical_Name,
	inner:     CPattern,
	span:      base.Source_Span,
}

CPattern_Or :: struct {
	alternatives: [dynamic]CPattern,
	span:         base.Source_Span,
}

CType :: union {
	^CType_Primitive,
	^CType_Applied,
	^CType_Function,
	^CType_Record,
	^CType_Tuple,
	^CType_Tag_Union,
	^CType_Effect_Row,
	^CType_Variable,
	^CType_Wildcard,
	^CType_Self,
}

CType_Primitive :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

CType_Applied :: struct {
	name: base.Intern_ID,
	args: [dynamic]CType,
	span: base.Source_Span,
}

CType_Function :: struct {
	params:  [dynamic]CType,
	effects: ^CType,
	return_: CType,
	span:    base.Source_Span,
}

CType_Record :: struct {
	fields:  [dynamic]CType_Field,
	rest:    base.Intern_ID,
	is_open: bool,
	span:    base.Source_Span,
}
CType_Tuple :: struct {
	elements: [dynamic]CType,
	span:     base.Source_Span,
}

CType_Field :: struct {
	name: base.Intern_ID,
	type: CType,
	span: base.Source_Span,
}

CType_Tag_Union :: struct {
	tags:    [dynamic]CType_Tag,
	rest:    base.Intern_ID,
	is_open: bool,
	span:    base.Source_Span,
}

CType_Tag :: struct {
	name:    base.Intern_ID,
	payload: [dynamic]CType,
	span:    base.Source_Span,
}

CType_Effect_Entry :: struct {
	name:      base.Intern_ID,
	type_args: [dynamic]CType,
	span:      base.Source_Span,
}

CType_Effect_Row :: struct {
	effects: [dynamic]CType_Effect_Entry,
	rest:    base.Intern_ID,
	is_open: bool,
	span:    base.Source_Span,
}

CType_Variable :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

CType_Wildcard :: struct {
	span: base.Source_Span,
}

CType_Self :: struct {
	span: base.Source_Span,
}

CFile :: struct {
	path:    string,
	decls:   [dynamic]CDecl,
	imports: [dynamic]base.Deferred_Import,
	span:    base.Source_Span,
}

