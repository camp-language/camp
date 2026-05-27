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
	doc_comment:    string,
	span:           base.Source_Span,
}

CDecl_Effect :: struct {
	name:        base.Canonical_Name,
	is_pub:      bool,
	operations:  [dynamic]CEffect_Op,
	type_params: [dynamic]frontend.Type_Param,
	doc_comment: string,
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
	name:        base.Canonical_Name,
	is_pub:      bool,
	parent:      base.Intern_ID,
	methods:     [dynamic]CTrait_Method,
	doc_comment: string,
	span:        base.Source_Span,
}

CTrait_Method :: struct {
	name:        base.Intern_ID,
	params:      [dynamic]CFunc_Param,
	return_type: ^CType,
	span:        base.Source_Span,
}

CDecl_Alias :: struct {
	name:        base.Canonical_Name,
	is_pub:      bool,
	target:      ^CType,
	doc_comment: string,
	type_params: [dynamic]frontend.Type_Param,
	span:        base.Source_Span,
}

CDecl_Newtype :: struct {
	name:           base.Canonical_Name,
	is_pub:         bool,
	pub_variants:   bool,
	type_params:    [dynamic]base.Intern_ID,
	inner_type:     ^CType,
	derive_targets: [dynamic]base.Intern_ID,
	doc_comment:    string,
	span:           base.Source_Span,
}

CDecl_Import :: struct {
	deferred:    base.Deferred_Import,
	doc_comment: string,
	span:        base.Source_Span,
}

CDecl_Test :: struct {
	name:        string,
	body:        CExpr,
	doc_comment: string,
	span:        base.Source_Span,
}

CDecl_Expect :: struct {
	condition:   CExpr,
	doc_comment: string,
	span:        base.Source_Span,
}

CDecl_Is_Impl :: struct {
	type_name:   base.Canonical_Name,
	trait_name:  base.Canonical_Name,
	methods:     [dynamic]CIs_Method,
	doc_comment: string,
	span:        base.Source_Span,
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
	rest:    base.Intern_ID,
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
	path:       string,
	decls:      [dynamic]CDecl,
	imports:    [dynamic]base.Deferred_Import,
	module_doc: string,
	span:       base.Source_Span,
}

cfile_destroy :: proc(f: ^CFile) {
	if f == nil do return
	for decl in f.decls do cdecl_destroy(decl)
	delete(f.decls)
	for imp in f.imports do delete(imp.names)
	delete(f.imports)
}

cdecl_destroy :: proc(d: CDecl) {
	if d == nil do return
	#partial switch v in d {
	case ^CDecl_Const:
		cexpr_destroy(v.body)
		if v.type_ann != nil {
			ctype_destroy(v.type_ann^)
			free(v.type_ann)
		}
		delete(v.derive_targets)
		delete(v.where_clauses)
		free(v)
	case ^CDecl_Effect:
		for op in v.operations {
			for param in op.params {
				if param.type_ann != nil {
					ctype_destroy(param.type_ann^)
					free(param.type_ann)
				}
			}
			delete(op.params)
			if op.return_type != nil {
				ctype_destroy(op.return_type^)
				free(op.return_type)
			}
			if op.return_effects != nil {
				ctype_destroy(op.return_effects^)
				free(op.return_effects)
			}
		}
		delete(v.operations)
		for tp in v.type_params do delete(tp.constraints)
		delete(v.type_params)
		free(v)
	case ^CDecl_Trait:
		for method in v.methods {
			for param in method.params {
				if param.type_ann != nil {
					ctype_destroy(param.type_ann^)
					free(param.type_ann)
				}
			}
			delete(method.params)
			if method.return_type != nil {
				ctype_destroy(method.return_type^)
				free(method.return_type)
			}
		}
		delete(v.methods)
		free(v)
	case ^CDecl_Is_Impl:
		for method in v.methods do cexpr_destroy(method.body)
		delete(v.methods)
		free(v)
	case ^CDecl_Alias:
		if v.target != nil {
			ctype_destroy(v.target^)
			free(v.target)
		}
		free(v)
	case ^CDecl_Newtype:
		delete(v.type_params)
		if v.inner_type != nil {
			ctype_destroy(v.inner_type^)
			free(v.inner_type)
		}
		delete(v.derive_targets)
		free(v)
	case ^CDecl_Import:
		delete(v.deferred.names)
		free(v)
	case ^CDecl_Test:
		cexpr_destroy(v.body)
		free(v)
	case ^CDecl_Expect:
		cexpr_destroy(v.condition)
		free(v)
	}
}

cexpr_destroy :: proc(e: CExpr) {
	if e == nil do return
	#partial switch v in e {
	case ^CExpr_Int:
		free(v)
	case ^CExpr_Float:
		free(v)
	case ^CExpr_String:
		free(v)
	case ^CExpr_Bool:
		free(v)
	case ^CExpr_Char:
		free(v)
	case ^CExpr_Tag:
		for arg in v.payload do cexpr_destroy(arg)
		delete(v.payload)
		free(v)
	case ^CExpr_Nominal_Construct:
		for arg in v.payload do cexpr_destroy(arg)
		delete(v.payload)
		free(v)
	case ^CExpr_Record:
		for field in v.fields do cexpr_destroy(field.value)
		delete(v.fields)
		cexpr_destroy(v.rest)
		free(v)
	case ^CExpr_Tuple:
		for el in v.elements do cexpr_destroy(el)
		delete(v.elements)
		free(v)
	case ^CExpr_List:
		for el in v.elements do cexpr_destroy(el)
		delete(v.elements)
		cexpr_destroy(v.rest)
		free(v)
	case ^CExpr_Name:
		free(v)
	case ^CExpr_Call:
		cexpr_destroy(v.callee)
		for arg in v.args do cexpr_destroy(arg)
		delete(v.args)
		free(v)
	case ^CExpr_Method_Call:
		cexpr_destroy(v.receiver)
		for arg in v.args do cexpr_destroy(arg)
		delete(v.args)
		free(v)
	case ^CExpr_Lambda:
		for tp in v.type_params do delete(tp.constraints)
		delete(v.type_params)
		for param in v.params {
			if param.type_ann != nil {
				ctype_destroy(param.type_ann^)
				free(param.type_ann)
			}
		}
		delete(v.params)
		if v.return_type != nil {
			ctype_destroy(v.return_type^)
			free(v.return_type)
		}
		if v.effects != nil {
			ctype_destroy(v.effects^)
			free(v.effects)
		}
		delete(v.where_clauses)
		cexpr_destroy(v.body)
		free(v)
	case ^CExpr_Block:
		for stmt in v.statements do cexpr_destroy(stmt)
		delete(v.statements)
		free(v)
	case ^CExpr_If:
		cexpr_destroy(v.condition)
		cexpr_destroy(v.then_branch)
		cexpr_destroy(v.else_branch)
		free(v)
	case ^CExpr_Match:
		cexpr_destroy(v.scrutinee)
		for arm in v.arms {
			cpattern_destroy(arm.pattern)
			cexpr_destroy(arm.guard)
			cexpr_destroy(arm.body)
		}
		delete(v.arms)
		free(v)
	case ^CExpr_BinOp:
		cexpr_destroy(v.left)
		cexpr_destroy(v.right)
		free(v)
	case ^CExpr_PrefixOp:
		cexpr_destroy(v.operand)
		free(v)
	case ^CExpr_Field_Access:
		cexpr_destroy(v.record)
		free(v)
	case ^CExpr_Field_Index:
		cexpr_destroy(v.record)
		free(v)
	case ^CExpr_Record_Update:
		cexpr_destroy(v.rest)
		for update in v.updates do cexpr_destroy(update.value)
		delete(v.updates)
		free(v)
	case ^CExpr_Assign:
		cexpr_destroy(v.target)
		cexpr_destroy(v.value)
		if v.type_ann != nil {
			ctype_destroy(v.type_ann^)
			free(v.type_ann)
		}
		free(v)
	case ^CExpr_Return:
		cexpr_destroy(v.value)
		free(v)
	case ^CExpr_Crash:
		cexpr_destroy(v.message)
		free(v)
	case ^CExpr_Todo:
		cexpr_destroy(v.message)
		free(v)
	case ^CExpr_Interpolated_String:
		for part in v.parts {
			#partial switch p in part {
			case ^CExpr_String_Literal:
				free(p)
			case CExpr:
				cexpr_destroy(p)
			}
		}
		delete(v.parts)
		free(v)
	case ^CExpr_Handle:
		delete(v.effects)
		cexpr_destroy(v.body)
		for arm in v.arms {
			delete(arm.params)
			cexpr_destroy(arm.body)
		}
		delete(v.arms)
		free(v)
	case ^CExpr_Perform:
		for arg in v.args do cexpr_destroy(arg)
		delete(v.args)
		free(v)
	case ^CExpr_Par:
		delete(v.names)
		for expr in v.expressions do cexpr_destroy(expr)
		delete(v.expressions)
		cexpr_destroy(v.for_iter)
		cexpr_destroy(v.for_body)
		free(v)
	case ^CExpr_For:
		cexpr_destroy(v.iterable)
		cexpr_destroy(v.body)
		free(v)
	}
}

cpattern_destroy :: proc(p: CPattern) {
	if p == nil do return
	#partial switch v in p {
	case ^CPattern_Tag:
		for elem in v.payload do cpattern_destroy(elem)
		delete(v.payload)
		free(v)
	case ^CPattern_Record:
		delete(v.fields)
		free(v)
	case ^CPattern_Tuple:
		for elem in v.elements do cpattern_destroy(elem)
		delete(v.elements)
		free(v)
	case ^CPattern_List:
		for elem in v.elements do cpattern_destroy(elem)
		delete(v.elements)
		cpattern_destroy(v.rest)
		free(v)
	case ^CPattern_Int:
		free(v)
	case ^CPattern_String:
		free(v)
	case ^CPattern_Bool:
		free(v)
	case ^CPattern_Char:
		free(v)
	case ^CPattern_Identifier:
		free(v)
	case ^CPattern_Wildcard:
		free(v)
	case ^CPattern_Destructure:
		cpattern_destroy(v.inner)
		free(v)
	case ^CPattern_Or:
		for elem in v.alternatives do cpattern_destroy(elem)
		delete(v.alternatives)
		free(v)
	}
}

ctype_destroy :: proc(t: CType) {
	if t == nil do return
	#partial switch v in t {
	case ^CType_Primitive:
		free(v)
	case ^CType_Variable:
		free(v)
	case ^CType_Wildcard:
		free(v)
	case ^CType_Self:
		free(v)
	case ^CType_Applied:
		for arg in v.args do ctype_destroy(arg)
		delete(v.args)
		free(v)
	case ^CType_Function:
		for param in v.params do ctype_destroy(param)
		delete(v.params)
		ctype_destroy(v.return_)
		if v.effects != nil {
			ctype_destroy(v.effects^)
			free(v.effects)
		}
		free(v)
	case ^CType_Record:
		for field in v.fields do ctype_destroy(field.type)
		delete(v.fields)
		free(v)
	case ^CType_Tuple:
		for el in v.elements do ctype_destroy(el)
		delete(v.elements)
		free(v)
	case ^CType_Tag_Union:
		for tag in v.tags {
			for payload in tag.payload do ctype_destroy(payload)
			delete(tag.payload)
		}
		delete(v.tags)
		free(v)
	case ^CType_Effect_Row:
		for entry in v.effects {
			for arg in entry.type_args do ctype_destroy(arg)
			delete(entry.type_args)
		}
		delete(v.effects)
		free(v)
	}
}

