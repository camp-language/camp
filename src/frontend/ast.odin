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
	^Decl_Is_Impl,
}

Decl_Const :: struct {
	name:          base.Intern_ID,
	is_pub:        bool,
	is_effectful:  bool,
	body:          Expr,
	type_ann:      ^Type,
	where_clauses: [dynamic]Where_Clause,
	doc_comment:   string,
	span:          base.Source_Span,
}

Where_Clause :: struct {
	type_param: base.Intern_ID,
	trait_name: base.Intern_ID,
	span:       base.Source_Span,
}

Decl_Effect :: struct {
	name:        base.Intern_ID,
	is_pub:      bool,
	operations:  [dynamic]Effect_Op,
	type_params: [dynamic]Type_Param,
	doc_comment: string,
	span:        base.Source_Span,
}

Effect_Op :: struct {
	name:           base.Intern_ID,
	is_effectful:   bool,
	params:         [dynamic]Func_Param,
	return_type:    ^Type,
	return_effects: ^Type,
	span:           base.Source_Span,
}

Decl_Trait :: struct {
	name:        base.Intern_ID,
	is_pub:      bool,
	parent:      base.Intern_ID,
	methods:     [dynamic]Trait_Method,
	doc_comment: string,
	span:        base.Source_Span,
}

Trait_Method :: struct {
	name:        base.Intern_ID,
	params:      [dynamic]Func_Param,
	return_type: ^Type,
	span:        base.Source_Span,
}

Decl_Alias :: struct {
	name:        base.Intern_ID,
	is_pub:      bool,
	target:      ^Type,
	doc_comment: string,
	type_params: [dynamic]Type_Param,
	span:        base.Source_Span,
}

Decl_Newtype :: struct {
	name:           base.Intern_ID,
	is_pub:         bool,
	pub_variants:   bool,
	type_params:    [dynamic]base.Intern_ID,
	inner_type:     ^Type,
	derive_targets: [dynamic]base.Intern_ID,
	doc_comment:    string,
	span:           base.Source_Span,
}

Import_Item :: union {
	base.Intern_ID,
	^Import_Variant_Group,
}

Import_Variant_Group :: struct {
	variants: [dynamic]base.Intern_ID,
	span:     base.Source_Span,
}

Decl_Import :: struct {
	module:      string,
	names:       [dynamic]Import_Item,
	alias:       base.Intern_ID,
	doc_comment: string,
	span:        base.Source_Span,
}

Decl_Test :: struct {
	name:        string,
	body:        Expr,
	doc_comment: string,
	span:        base.Source_Span,
}

Decl_Expect :: struct {
	condition:   Expr,
	doc_comment: string,
	span:        base.Source_Span,
}

Decl_Is_Impl :: struct {
	type_name:   base.Intern_ID,
	trait_name:  base.Intern_ID,
	methods:     [dynamic]Is_Method,
	doc_comment: string,
	span:        base.Source_Span,
}

Is_Method :: struct {
	name: base.Intern_ID,
	body: Expr,
	span: base.Source_Span,
}

Expr :: union {
	^Expr_Int,
	^Expr_Float,
	^Expr_String,
	^Expr_Char,
	^Expr_Bool,
	^Expr_Tag,
	^Expr_Nominal_Construct,
	^Expr_Record,
	^Expr_Tuple,
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
	^Expr_Todo,
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

Expr_Char :: struct {
	value: u8,
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
	variant:   base.Intern_ID, // 0 = simple wrap @TypeName(args), non-zero = @TypeName.Variant(args)
	payload:   [dynamic]Expr,
	span:      base.Source_Span,
}

Expr_Record :: struct {
	fields:  [dynamic]Record_Field,
	rest:    Expr,
	is_open: bool,
	span:    base.Source_Span,
}
Expr_Tuple :: struct {
	elements: [dynamic]Expr,
	span:     base.Source_Span,
}

Record_Field :: struct {
	name:  base.Intern_ID,
	value: Expr,
	span:  base.Source_Span,
}

Expr_List :: struct {
	elements: [dynamic]Expr,
	rest:     Expr,
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

Dispatch_Kind :: enum {
	Nominal, // obj.method(args) — type promised it
	Lexical, // obj->func(args) — scope provides function
	Structural, // obj.(field)(args) — value stores function
}

Expr_Method_Call :: struct {
	receiver:     Expr,
	method:       base.Intern_ID,
	args:         [dynamic]Expr,
	is_effectful: bool,
	dispatch:     Dispatch_Kind,
	span:         base.Source_Span,
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
	span:        base.Source_Span,
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
	^Pattern_Tuple,
	^Pattern_List,
	^Pattern_Int,
	^Pattern_String,
	^Pattern_Char,
	^Pattern_Bool,
	^Pattern_Identifier,
	^Pattern_Wildcard,
	^Pattern_Destructure,
	^Pattern_Or,
	^Pattern_As,
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
	rest:    base.Intern_ID,
}
Pattern_Tuple :: struct {
	elements: [dynamic]Pattern,
	span:     base.Source_Span,
}

Pattern_Field :: struct {
	name:    base.Intern_ID,
	binding: base.Intern_ID,
	span:    base.Source_Span,
}

Pattern_List :: struct {
	elements: [dynamic]Pattern,
	rest:     Pattern,
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

Pattern_Char :: struct {
	value: u8,
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

Pattern_As :: struct {
	name:  base.Intern_ID,
	inner: Pattern,
	span:  base.Source_Span,
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

Expr_Todo :: struct {
	message: Expr, // nil for bare `todo`, non-nil for `todo "msg"`
	span:    base.Source_Span,
}

Expr_Interpolated_String :: struct {
	parts: [dynamic]String_Part,
	span:  base.Source_Span,
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
	effects: [dynamic]base.Intern_ID,
	body:    Expr,
	arms:    [dynamic]Handler_Arm,
	span:    base.Source_Span,
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
	names:       [dynamic]base.Intern_ID, // field names for par { name: expr, ... }
	expressions: [dynamic]Expr, // for par { e1, e2 }
	for_var:     base.Intern_ID, // 0 if not par-for
	for_iter:    Expr, // the xs in "par for x in xs"
	for_body:    Expr, // the body in "par for x in xs { body }"
	span:        base.Source_Span,
}

Type :: union {
	^Type_Primitive,
	^Type_Applied,
	^Type_Function,
	^Type_Record,
	^Type_Tuple,
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
Type_Tuple :: struct {
	elements: [dynamic]Type,
	span:     base.Source_Span,
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
	type_args: [dynamic]Type, // Type from ast.odin — empty for unparameterized
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

Deps_Entry :: struct {
	alias: string,
	uri:   string,
}

File :: struct {
	path:       string,
	decls:      [dynamic]Decl,
	module_doc: string,
	deps:       [dynamic]Deps_Entry,
	span:       base.Source_Span,
}

file_destroy :: proc(f: ^File) {
	if f == nil do return
	for decl in f.decls do decl_destroy(decl)
	delete(f.decls)
}

decl_destroy :: proc(d: Decl) {
	if d == nil do return
	#partial switch v in d {
	case ^Decl_Const:
		expr_destroy(v.body)
		if v.type_ann != nil do type_destroy(v.type_ann^)
		delete(v.where_clauses)
		free(v)
	case ^Decl_Effect:
		for op in v.operations {
			for param in op.params do if param.type_ann != nil do type_destroy(param.type_ann^)
			delete(op.params)
			if op.return_type != nil do type_destroy(op.return_type^)
			if op.return_effects != nil do type_destroy(op.return_effects^)
		}
		delete(v.operations)
		for tp in v.type_params do delete(tp.constraints)
		delete(v.type_params)
		free(v)
	case ^Decl_Trait:
		for method in v.methods {
			for param in method.params do if param.type_ann != nil do type_destroy(param.type_ann^)
			delete(method.params)
			if method.return_type != nil do type_destroy(method.return_type^)
		}
		delete(v.methods)
		free(v)
	case ^Decl_Alias:
		if v.target != nil do type_destroy(v.target^)
		free(v)
	case ^Decl_Newtype:
		delete(v.type_params)
		if v.inner_type != nil do type_destroy(v.inner_type^)
		delete(v.derive_targets)
		free(v)
	case ^Decl_Import:
		for name in v.names {
			#partial switch item in name {
			case ^Import_Variant_Group:
				delete(item.variants)
				free(item)
			}
		}
		delete(v.names)
		free(v)
	case ^Decl_Test:
		expr_destroy(v.body)
		free(v)
	case ^Decl_Expect:
		expr_destroy(v.condition)
		free(v)
	case ^Decl_Is_Impl:
		for method in v.methods do expr_destroy(method.body)
		delete(v.methods)
		free(v)
	}
}

expr_destroy :: proc(e: Expr) {
	if e == nil do return
	#partial switch v in e {
	case ^Expr_Int:
		free(v)
	case ^Expr_Float:
		free(v)
	case ^Expr_String:
		free(v)
	case ^Expr_Char:
		free(v)
	case ^Expr_Bool:
		free(v)
	case ^Expr_Identifier:
		free(v)
	case ^Expr_Dollar_Identifier:
		free(v)
	case ^Expr_Tag:
		for arg in v.payload do expr_destroy(arg)
		delete(v.payload)
		free(v)
	case ^Expr_Nominal_Construct:
		for arg in v.payload do expr_destroy(arg)
		delete(v.payload)
		free(v)
	case ^Expr_Record:
		for field in v.fields do expr_destroy(field.value)
		delete(v.fields)
		expr_destroy(v.rest)
		free(v)
	case ^Expr_Tuple:
		for el in v.elements do expr_destroy(el)
		delete(v.elements)
		free(v)
	case ^Expr_List:
		for el in v.elements do expr_destroy(el)
		delete(v.elements)
		expr_destroy(v.rest)
		free(v)
	case ^Expr_Call:
		expr_destroy(v.callee)
		for arg in v.args do expr_destroy(arg)
		delete(v.args)
		free(v)
	case ^Expr_Method_Call:
		expr_destroy(v.receiver)
		for arg in v.args do expr_destroy(arg)
		delete(v.args)
		free(v)
	case ^Expr_Lambda:
		for tp in v.type_params do delete(tp.constraints)
		delete(v.type_params)
		for param in v.params do if param.type_ann != nil do type_destroy(param.type_ann^)
		delete(v.params)
		if v.return_type != nil do type_destroy(v.return_type^)
		if v.effects != nil do type_destroy(v.effects^)
		delete(v.where_clauses)
		expr_destroy(v.body)
		free(v)
	case ^Expr_Block:
		for stmt in v.statements do expr_destroy(stmt)
		delete(v.statements)
		free(v)
	case ^Expr_If:
		expr_destroy(v.condition)
		expr_destroy(v.then_branch)
		expr_destroy(v.else_branch)
		free(v)
	case ^Expr_Match:
		expr_destroy(v.scrutinee)
		for arm in v.arms {
			pattern_destroy(arm.pattern)
			expr_destroy(arm.guard)
			expr_destroy(arm.body)
		}
		delete(v.arms)
		free(v)
	case ^Expr_BinOp:
		expr_destroy(v.left)
		expr_destroy(v.right)
		free(v)
	case ^Expr_PrefixOp:
		expr_destroy(v.operand)
		free(v)
	case ^Expr_Field_Access:
		expr_destroy(v.record)
		free(v)
	case ^Expr_Record_Update:
		expr_destroy(v.rest)
		for update in v.updates do expr_destroy(update.value)
		delete(v.updates)
		free(v)
	case ^Expr_Assign:
		expr_destroy(v.target)
		expr_destroy(v.value)
		if v.type_ann != nil do type_destroy(v.type_ann^)
		free(v)
	case ^Expr_Return:
		expr_destroy(v.value)
		free(v)
	case ^Expr_Crash:
		expr_destroy(v.message)
		free(v)
	case ^Expr_Todo:
		expr_destroy(v.message)
		free(v)
	case ^Expr_Interpolated_String:
		for part in v.parts {
			#partial switch p in part {
			case ^String_Segment:
				free(p)
			case Expr:
				expr_destroy(p)
			}
		}
		delete(v.parts)
		free(v)
	case ^Expr_Handle:
		delete(v.effects)
		expr_destroy(v.body)
		for arm in v.arms {
			delete(arm.params)
			expr_destroy(arm.body)
		}
		delete(v.arms)
		free(v)
	case ^Expr_Par:
		delete(v.names)
		for expr in v.expressions do expr_destroy(expr)
		delete(v.expressions)
		expr_destroy(v.for_iter)
		expr_destroy(v.for_body)
		free(v)
	case ^Expr_Dot_Lambda:
		expr_destroy(v.body)
		free(v)
	case ^Expr_For:
		expr_destroy(v.iterable)
		expr_destroy(v.body)
		free(v)
	}
}

pattern_destroy :: proc(p: Pattern) {
	if p == nil do return
	#partial switch v in p {
	case ^Pattern_Tag:
		for elem in v.payload do pattern_destroy(elem)
		delete(v.payload)
		free(v)
	case ^Pattern_Record:
		delete(v.fields)
		free(v)
	case ^Pattern_Tuple:
		for elem in v.elements do pattern_destroy(elem)
		delete(v.elements)
		free(v)
	case ^Pattern_List:
		for elem in v.elements do pattern_destroy(elem)
		delete(v.elements)
		pattern_destroy(v.rest)
		free(v)
	case ^Pattern_Int:
		free(v)
	case ^Pattern_String:
		free(v)
	case ^Pattern_Char:
		free(v)
	case ^Pattern_Bool:
		free(v)
	case ^Pattern_Identifier:
		free(v)
	case ^Pattern_Wildcard:
		free(v)
	case ^Pattern_Destructure:
		pattern_destroy(v.inner)
		free(v)
	case ^Pattern_Or:
		for elem in v.alternatives do pattern_destroy(elem)
		delete(v.alternatives)
		free(v)
	}
}

type_destroy :: proc(t: Type) {
	if t == nil do return
	#partial switch v in t {
	case ^Type_Primitive:
		free(v)
	case ^Type_Variable:
		free(v)
	case ^Type_Wildcard:
		free(v)
	case ^Type_Self:
		free(v)
	case ^Type_Applied:
		for arg in v.args do type_destroy(arg)
		delete(v.args)
		free(v)
	case ^Type_Function:
		for param in v.params do type_destroy(param)
		delete(v.params)
		type_destroy(v.return_)
		if v.effects != nil do type_destroy(v.effects^)
		free(v)
	case ^Type_Record:
		for field in v.fields do type_destroy(field.type)
		delete(v.fields)
		free(v)
	case ^Type_Tuple:
		for el in v.elements do type_destroy(el)
		delete(v.elements)
		free(v)
	case ^Type_Tag_Union:
		for tag in v.tags {
			for payload in tag.payload do type_destroy(payload)
			delete(tag.payload)
		}
		delete(v.tags)
		free(v)
	case ^Type_Effect_Row:
		for entry in v.effects {
			for arg in entry.type_args do type_destroy(arg)
			delete(entry.type_args)
		}
		delete(v.effects)
		free(v)
	}
}

