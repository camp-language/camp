package frontend

import "camp:base"

Decl :: union {
	^Decl_Const,
	^Decl_Effect,
	^Decl_Trait,
	^Decl_Alias,
	^Decl_Newtype,
	^Decl_Import,
	^Decl_Test,
	^Decl_Expect,
}

Decl_Const :: struct {
	name:          base.Intern_ID,
	is_pub:        bool,
	is_effectful:  bool,
	body:          Expr,
	type_ann:      ^Type,
	where_clauses: [dynamic]Where_Clause,
	span:          base.Source_Span,
}

Where_Clause :: struct {
	type_param:  base.Intern_ID,
	trait_name:  base.Intern_ID,
	span:        base.Source_Span,
}

Decl_Effect :: struct {
	name:       base.Intern_ID,
	is_pub:     bool,
	operations: [dynamic]Effect_Op,
	type_params: [dynamic]Type_Param,
	span:       base.Source_Span,
}

Effect_Op :: struct {
	name:          base.Intern_ID,
	is_effectful:  bool,
	params:        [dynamic]Func_Param,
	return_type:   ^Type,
	return_effects: ^Type,
	span:          base.Source_Span,
}

Decl_Trait :: struct {
	name:    base.Intern_ID,
	is_pub:  bool,
	parent:  base.Intern_ID,
	methods: [dynamic]Trait_Method,
	span:    base.Source_Span,
}

Trait_Method :: struct {
	name:        base.Intern_ID,
	params:      [dynamic]Func_Param,
	return_type: ^Type,
	span:        base.Source_Span,
}

Decl_Alias :: struct {
	name:   base.Intern_ID,
	is_pub: bool,
	target: ^Type,
	span:   base.Source_Span,
}

Decl_Newtype :: struct {
	name:           base.Intern_ID,
	is_pub:         bool,
	pub_variants:   bool,
	type_params:    [dynamic]base.Intern_ID,
	trait_conforms: [dynamic]base.Intern_ID,
	inner_type:     ^Type,
	derive_targets: [dynamic]base.Intern_ID,
	span:           base.Source_Span,
}

Decl_Import :: struct {
	module:            string,
	exposing:          [dynamic]base.Intern_ID,
	nominal_exposing:  [dynamic]Import_Nominal_Expose,
	alias:             base.Intern_ID,
	is_unsafe:         bool,
	span:              base.Source_Span,
}

Import_Nominal_Expose :: struct {
	type_name: base.Intern_ID,
	variants:  [dynamic]base.Intern_ID,
}

Decl_Test :: struct {
	name: string,
	body: Expr,
	span: base.Source_Span,
}

Decl_Expect :: struct {
	condition: Expr,
	span:      base.Source_Span,
}

Expr :: union {
	^Expr_Int,
	^Expr_Float,
	^Expr_String,
	^Expr_Bool,
	^Expr_Tag,
	^Expr_Nominal_Construct,
	^Expr_Record,
	^Expr_List,
	^Expr_Identifier,
	^Expr_Dollar_Identifier,
	^Expr_Call,
	^Expr_Method_Call,
	^Expr_Lambda,
	^Expr_Block,
	^Expr_If,
	^Expr_Match,
	^Expr_BinOp,
	^Expr_PrefixOp,
	^Expr_Field_Access,
	^Expr_Record_Update,
	^Expr_Assign,
	^Expr_Return,
	^Expr_Crash,
	^Expr_Interpolated_String,
	^Expr_Handle,
	^Expr_Par,
	^Expr_Dot_Lambda,
	^Expr_For,
}

Expr_Int :: struct {
	value: i64,
	span:  base.Source_Span,
}

Expr_Float :: struct {
	value: f64,
	span:  base.Source_Span,
}

Expr_String :: struct {
	value: string,
	span:  base.Source_Span,
}

Expr_Bool :: struct {
	value: bool,
	span:  base.Source_Span,
}

Expr_Tag :: struct {
	name:    base.Intern_ID,
	payload: [dynamic]Expr,
	span:    base.Source_Span,
}

Expr_Nominal_Construct :: struct {
	type_name: base.Intern_ID,
	variant:   base.Intern_ID,  // 0 = simple wrap @TypeName(args), non-zero = @TypeName.Variant(args)
	payload:   [dynamic]Expr,
	span:      base.Source_Span,
}

Expr_Record :: struct {
	fields:  [dynamic]Record_Field,
	rest:    Expr,
	is_open: bool,
	span:    base.Source_Span,
}

Record_Field :: struct {
	name:  base.Intern_ID,
	value: Expr,
	span:  base.Source_Span,
}

Expr_List :: struct {
	elements: [dynamic]Expr,
	span:     base.Source_Span,
}

Expr_Identifier :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

Expr_Dollar_Identifier :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

Expr_Call :: struct {
	callee: Expr,
	args:   [dynamic]Expr,
	span:   base.Source_Span,
}

Expr_Method_Call :: struct {
	receiver:      Expr,
	method:        base.Intern_ID,
	args:          [dynamic]Expr,
	is_effectful:  bool,
	span:          base.Source_Span,
}

Expr_Lambda :: struct {
	type_params:   [dynamic]Type_Param,
	params:        [dynamic]Func_Param,
	return_type:   ^Type,
	effects:       ^Type,
	where_clauses: [dynamic]Where_Clause,
	body:          Expr,
	span:          base.Source_Span,
}

Type_Param :: struct {
	name:        base.Intern_ID,
	constraints: [dynamic]base.Intern_ID,
	is_effect:   bool,
}

Func_Param :: struct {
	name:     base.Intern_ID,
	type_ann: ^Type,
	span:     base.Source_Span,
}

Expr_Block :: struct {
	statements: [dynamic]Expr,
	span:       base.Source_Span,
}

Expr_If :: struct {
	condition:   Expr,
	then_branch: Expr,
	else_branch: Expr,
	span:       base.Source_Span,
}

Expr_Match :: struct {
	scrutinee: Expr,
	arms:      [dynamic]Match_Arm,
	span:      base.Source_Span,
}

Match_Arm :: struct {
	pattern: Pattern,
	guard:   Expr,
	body:    Expr,
	span:    base.Source_Span,
}

Pattern :: union {
	^Pattern_Tag,
	^Pattern_Record,
	^Pattern_List,
	^Pattern_Int,
	^Pattern_String,
	^Pattern_Bool,
	^Pattern_Identifier,
	^Pattern_Wildcard,
	^Pattern_Destructure,
	^Pattern_Or,
}

Pattern_Tag :: struct {
	name:    base.Intern_ID,
	payload: [dynamic]Pattern,
	span:    base.Source_Span,
}

Pattern_Record :: struct {
	fields:  [dynamic]Pattern_Field,
	is_open: bool,
	span:    base.Source_Span,
}

Pattern_Field :: struct {
	name:    base.Intern_ID,
	binding: base.Intern_ID,
	span:    base.Source_Span,
}

Pattern_List :: struct {
	elements: [dynamic]Pattern,
	span:     base.Source_Span,
}

Pattern_Int :: struct {
	value: i64,
	span:  base.Source_Span,
}

Pattern_String :: struct {
	value: string,
	span:  base.Source_Span,
}

Pattern_Bool :: struct {
	value: bool,
	span:  base.Source_Span,
}

Pattern_Identifier :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

Pattern_Wildcard :: struct {
	span: base.Source_Span,
}

Pattern_Destructure :: struct {
	type_name: base.Intern_ID,
	inner:     Pattern,
	span:      base.Source_Span,
}

Pattern_Or :: struct {
	alternatives: [dynamic]Pattern,
	span:         base.Source_Span,
}

Expr_BinOp :: struct {
	op:    base.Token_Kind,
	left:  Expr,
	right: Expr,
	span:  base.Source_Span,
}

Expr_PrefixOp :: struct {
	op:      base.Token_Kind,
	operand: Expr,
	span:    base.Source_Span,
}

Expr_Field_Access :: struct {
	record: Expr,
	field:  base.Intern_ID,
	span:   base.Source_Span,
}

Expr_Record_Update :: struct {
	rest:    Expr,
	updates: [dynamic]Record_Field,
	span:    base.Source_Span,
}

Expr_Assign :: struct {
	target:   Expr,
	value:    Expr,
	type_ann: ^Type,
	span:     base.Source_Span,
}

Expr_Return :: struct {
	value: Expr,
	span:  base.Source_Span,
}

Expr_Crash :: struct {
	message: Expr,
	span:    base.Source_Span,
}

Expr_Interpolated_String :: struct {
	parts:        [dynamic]String_Part,
	is_raw:       bool,
	is_multiline: bool,
	span:         base.Source_Span,
}

String_Part :: union {
	^String_Segment,
	Expr,
}

String_Segment :: struct {
	text: string,
	span: base.Source_Span,
}

Expr_Handle :: struct {
	effect:     base.Intern_ID,
	is_shallow: bool,
	body:       Expr,
	arms:       [dynamic]Handler_Arm,
	span:       base.Source_Span,
}

Expr_Dot_Lambda :: struct {
	body: Expr,
	span: base.Source_Span,
}

Handler_Arm :: struct {
	op:     base.Intern_ID,
	params: [dynamic]base.Intern_ID,
	body:   Expr,
	span:   base.Source_Span,
}

Expr_For :: struct {
	var:      base.Intern_ID,
	iterable: Expr,
	body:     Expr,
	span:     base.Source_Span,
}

Expr_Par :: struct {
	expressions: [dynamic]Expr,  // for par { e1, e2 }
	for_var:     base.Intern_ID,      // 0 if not par-for
	for_iter:    Expr,            // the xs in "par for x in xs"
	for_body:    Expr,            // the body in "par for x in xs { body }"
	span:        base.Source_Span,
}

Type :: union {
	^Type_Primitive,
	^Type_Applied,
	^Type_Function,
	^Type_Record,
	^Type_Tag_Union,
	^Type_Effect_Row,
	^Type_Variable,
	^Type_Wildcard,
	^Type_Self,
}

Type_Primitive :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

Type_Applied :: struct {
	name: base.Intern_ID,
	args: [dynamic]Type,
	span: base.Source_Span,
}

Type_Function :: struct {
	params:  [dynamic]Type,
	effects: ^Type,
	return_: Type,
	span:    base.Source_Span,
}

Type_Record :: struct {
	fields:  [dynamic]Type_Field,
	rest:    base.Intern_ID,
	is_open: bool,
	span:    base.Source_Span,
}

Type_Field :: struct {
	name: base.Intern_ID,
	type: Type,
	span: base.Source_Span,
}

Type_Tag_Union :: struct {
	tags:    [dynamic]Type_Tag,
	rest:    base.Intern_ID,
	is_open: bool,
	span:    base.Source_Span,
}

Type_Tag :: struct {
	name:    base.Intern_ID,
	payload: [dynamic]Type,
	span:    base.Source_Span,
}

Type_Effect_Entry :: struct {
	name:      base.Intern_ID,
	type_args: [dynamic]Type,  // Type from ast.odin — empty for unparameterized
	span:      base.Source_Span,
}

Type_Effect_Row :: struct {
	effects: [dynamic]Type_Effect_Entry,
	rest:    base.Intern_ID,
	is_open: bool,
	span:    base.Source_Span,
}

Type_Variable :: struct {
	name: base.Intern_ID,
	span: base.Source_Span,
}

Type_Wildcard :: struct {
	span: base.Source_Span,
}

Type_Self :: struct {
	span: base.Source_Span,
}

File :: struct {
	path:  string,
	decls: [dynamic]Decl,
	span:  base.Source_Span,
}
