package camp

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
	name:          Intern_ID,
	is_pub:        bool,
	is_effectful:  bool,
	body:          Expr,
	type_ann:      ^Type,
	span:          Source_Span,
}

Decl_Effect :: struct {
	name:       Intern_ID,
	is_pub:     bool,
	operations: [dynamic]Effect_Op,
	span:       Source_Span,
}

Effect_Op :: struct {
	name:          Intern_ID,
	is_effectful:  bool,
	params:        [dynamic]Func_Param,
	return_type:   ^Type,
	return_effects: ^Type,
	span:          Source_Span,
}

Decl_Trait :: struct {
	name:    Intern_ID,
	is_pub:  bool,
	parent:  Intern_ID,
	methods: [dynamic]Trait_Method,
	span:    Source_Span,
}

Trait_Method :: struct {
	name:        Intern_ID,
	params:      [dynamic]Func_Param,
	return_type: ^Type,
	span:        Source_Span,
}

Decl_Alias :: struct {
	name:   Intern_ID,
	is_pub: bool,
	target: ^Type,
	span:   Source_Span,
}

Decl_Newtype :: struct {
	name:           Intern_ID,
	is_pub:         bool,
	pub_variants:   bool,
	type_params:    [dynamic]Intern_ID,
	trait_conforms: [dynamic]Intern_ID,
	inner_type:     ^Type,
	derive_targets: [dynamic]Intern_ID,
	span:           Source_Span,
}

Decl_Import :: struct {
	module:    string,
	exposing:  [dynamic]Intern_ID,
	alias:     Intern_ID,
	is_unsafe: bool,
	span:      Source_Span,
}

Decl_Test :: struct {
	name: string,
	body: Expr,
	span: Source_Span,
}

Decl_Expect :: struct {
	condition: Expr,
	span:      Source_Span,
}

Expr :: union {
	^Expr_Int,
	^Expr_Float,
	^Expr_String,
	^Expr_Bool,
	^Expr_Tag,
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
	^Expr_Interpolate,
	^Expr_Handle,
	^Expr_Dot_Lambda,
}

Expr_Int :: struct {
	value: i64,
	span:  Source_Span,
}

Expr_Float :: struct {
	value: f64,
	span:  Source_Span,
}

Expr_String :: struct {
	value: string,
	span:  Source_Span,
}

Expr_Bool :: struct {
	value: bool,
	span:  Source_Span,
}

Expr_Tag :: struct {
	name:    Intern_ID,
	payload: [dynamic]Expr,
	span:    Source_Span,
}

Expr_Record :: struct {
	fields:  [dynamic]Record_Field,
	rest:    Expr,
	is_open: bool,
	span:    Source_Span,
}

Record_Field :: struct {
	name:  Intern_ID,
	value: Expr,
	span:  Source_Span,
}

Expr_List :: struct {
	elements: [dynamic]Expr,
	span:     Source_Span,
}

Expr_Identifier :: struct {
	name: Intern_ID,
	span: Source_Span,
}

Expr_Dollar_Identifier :: struct {
	name: Intern_ID,
	span: Source_Span,
}

Expr_Call :: struct {
	callee: Expr,
	args:   [dynamic]Expr,
	span:   Source_Span,
}

Expr_Method_Call :: struct {
	receiver:      Expr,
	method:        Intern_ID,
	args:          [dynamic]Expr,
	is_effectful:  bool,
	span:          Source_Span,
}

Expr_Lambda :: struct {
	type_params: [dynamic]Type_Param,
	params:     [dynamic]Func_Param,
	return_type: ^Type,
	effects:    ^Type,
	body:       Expr,
	span:       Source_Span,
}

Type_Param :: struct {
	name:        Intern_ID,
	constraints: [dynamic]Intern_ID,
}

Func_Param :: struct {
	name:     Intern_ID,
	type_ann: ^Type,
	span:     Source_Span,
}

Expr_Block :: struct {
	statements: [dynamic]Expr,
	span:       Source_Span,
}

Expr_If :: struct {
	condition:   Expr,
	then_branch: Expr,
	else_branch: Expr,
	span:       Source_Span,
}

Expr_Match :: struct {
	scrutinee: Expr,
	arms:      [dynamic]Match_Arm,
	span:      Source_Span,
}

Match_Arm :: struct {
	pattern: Pattern,
	body:    Expr,
	span:    Source_Span,
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
}

Pattern_Tag :: struct {
	name:    Intern_ID,
	payload: [dynamic]Pattern,
	span:    Source_Span,
}

Pattern_Record :: struct {
	fields:  [dynamic]Pattern_Field,
	is_open: bool,
	span:    Source_Span,
}

Pattern_Field :: struct {
	name:    Intern_ID,
	binding: Intern_ID,
	span:    Source_Span,
}

Pattern_List :: struct {
	elements: [dynamic]Pattern,
	span:     Source_Span,
}

Pattern_Int :: struct {
	value: i64,
	span:  Source_Span,
}

Pattern_String :: struct {
	value: string,
	span:  Source_Span,
}

Pattern_Bool :: struct {
	value: bool,
	span:  Source_Span,
}

Pattern_Identifier :: struct {
	name: Intern_ID,
	span: Source_Span,
}

Pattern_Wildcard :: struct {
	span: Source_Span,
}

Pattern_Destructure :: struct {
	type_name: Intern_ID,
	inner:     Pattern,
	span:      Source_Span,
}

Expr_BinOp :: struct {
	op:    Token_Kind,
	left:  Expr,
	right: Expr,
	span:  Source_Span,
}

Expr_PrefixOp :: struct {
	op:      Token_Kind,
	operand: Expr,
	span:    Source_Span,
}

Expr_Field_Access :: struct {
	record: Expr,
	field:  Intern_ID,
	span:   Source_Span,
}

Expr_Record_Update :: struct {
	rest:    Expr,
	updates: [dynamic]Record_Field,
	span:    Source_Span,
}

Expr_Assign :: struct {
	target: Expr,
	value:  Expr,
	span:   Source_Span,
}

Expr_Return :: struct {
	value: Expr,
	span:  Source_Span,
}

Expr_Crash :: struct {
	message: Expr,
	span:    Source_Span,
}

Expr_Interpolate :: struct {
	parts: [dynamic]Expr,
	span:  Source_Span,
}

Expr_Handle :: struct {
	effect:     Intern_ID,
	is_shallow: bool,
	body:       Expr,
	arms:       [dynamic]Handler_Arm,
	span:       Source_Span,
}

Expr_Dot_Lambda :: struct {
	body: Expr,
	span: Source_Span,
}

Handler_Arm :: struct {
	op:     Intern_ID,
	params: [dynamic]Intern_ID,
	body:   Expr,
	span:   Source_Span,
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
	name: Intern_ID,
	span: Source_Span,
}

Type_Applied :: struct {
	name: Intern_ID,
	args: [dynamic]Type,
	span: Source_Span,
}

Type_Function :: struct {
	params:  [dynamic]Type,
	effects: ^Type,
	return_: Type,
	span:    Source_Span,
}

Type_Record :: struct {
	fields:  [dynamic]Type_Field,
	rest:    Intern_ID,
	is_open: bool,
	span:    Source_Span,
}

Type_Field :: struct {
	name: Intern_ID,
	type: Type,
	span: Source_Span,
}

Type_Tag_Union :: struct {
	tags:    [dynamic]Type_Tag,
	rest:    Intern_ID,
	is_open: bool,
	span:    Source_Span,
}

Type_Tag :: struct {
	name:    Intern_ID,
	payload: [dynamic]Type,
	span:    Source_Span,
}

Type_Effect_Entry :: struct {
	name:      Intern_ID,
	type_args: [dynamic]Type,  // Type from ast.odin — empty for unparameterized
	span:      Source_Span,
}

Type_Effect_Row :: struct {
	effects: [dynamic]Type_Effect_Entry,
	rest:    Intern_ID,
	is_open: bool,
	span:    Source_Span,
}

Type_Variable :: struct {
	name: Intern_ID,
	span: Source_Span,
}

Type_Wildcard :: struct {
	span: Source_Span,
}

Type_Self :: struct {
	span: Source_Span,
}

File :: struct {
	path:  string,
	decls: [dynamic]Decl,
	span:  Source_Span,
}
