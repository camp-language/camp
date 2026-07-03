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
	^TExpr_Tuple,
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
	^TExpr_Field_Index,
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
	value: i64,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_Float :: struct {
	value: f64,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_String :: struct {
	value: string,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_Bool :: struct {
	value: bool,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
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
	type_name:     base.Canonical_Name,
	variant:       base.Intern_ID,
	payload:       [dynamic]TExpr,
	resolved_type: Type_ID,
	span:          base.Source_Span,
}

TExpr_Record :: struct {
	fields:  [dynamic]TRecord_Field,
	rest:    TExpr,
	is_open: bool,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
}
TExpr_Tuple :: struct {
	elements: [dynamic]TExpr,
	type_:    base.IR_Type,
	eff_:     base.IR_Type,
	span:     base.Source_Span,
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
	name:  base.Intern_ID,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
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
	span:      base.Source_Span,
}

TMatch_Arm :: struct {
	pattern: TPattern,
	guard:   TExpr, // nil when the arm has no `if` guard
	body:    TExpr,
	span:    base.Source_Span,
}

TPattern :: union {
	^TPattern_Tag,
	^TPattern_Record,
	^TPattern_Tuple,
	^TPattern_List,
	^TPattern_Int,
	^TPattern_String,
	^TPattern_Bool,
	^TPattern_Char,
	^TPattern_Identifier,
	^TPattern_Wildcard,
	^TPattern_Destructure,
	^TPattern_Or,
	^TPattern_As,
	^TPattern_Interpolated_String,
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
	rest:    base.Intern_ID,
}
TPattern_Tuple :: struct {
	elements: [dynamic]TPattern,
	span:     base.Source_Span,
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

TPattern_As :: struct {
	name:  base.Intern_ID,
	inner: TPattern,
	span:  base.Source_Span,
}

TPattern_Interpolated_String :: struct {
	parts: [dynamic]TExpr_String_Part,
	span:  base.Source_Span,
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
	op:      base.Token_Kind,
	operand: TExpr,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
}

TExpr_Field_Access :: struct {
	record: TExpr,
	field:  base.Intern_ID,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	span:   base.Source_Span,
}
TExpr_Field_Index :: struct {
	record:      TExpr,
	field_index: int,
	type_:       base.IR_Type,
	eff_:        base.IR_Type,
	span:        base.Source_Span,
}

TExpr_Record_Update :: struct {
	rest:    TExpr,
	updates: [dynamic]TRecord_Field,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
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
	TPattern,
}

TExpr_String_Literal :: struct {
	value: string,
	type_: base.IR_Type,
	eff_:  base.IR_Type,
	span:  base.Source_Span,
}

TExpr_String_Expr :: struct {
	expr:         TExpr,
	needs_to_str: bool,
	display_impl: base.Canonical_Name,
}

TExpr_Handle :: struct {
	effects: [dynamic]base.Canonical_Name,
	body:    TExpr,
	arms:    [dynamic]THandler_Arm,
	type_:   base.IR_Type,
	eff_:    base.IR_Type,
	span:    base.Source_Span,
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
	^TDecl_Effect_Alias,
}

TDecl_Const :: struct {
	name:           base.Canonical_Name,
	is_pub:         bool,
	is_effectful:   bool,
	type_ann:       ^CType,
	body:           TExpr,
	type_:          base.IR_Type,
	eff_:           base.IR_Type,
	derive_targets: [dynamic]base.Intern_ID,
	span:           base.Source_Span,
}

TDecl_Effect :: struct {
	name:        base.Canonical_Name,
	is_pub:      bool,
	operations:  [dynamic]TEffect_Op,
	type_params: [dynamic]frontend.Type_Param,
	span:        base.Source_Span,
}

TDecl_Effect_Alias :: struct {
	name:   base.Canonical_Name,
	target: ^CType,
	is_pub: bool,
	span:   base.Source_Span,
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
	condition:   TExpr,
	doc_comment: string,
	source_text: string,
	span:        base.Source_Span,
}

TDecl_Is_Impl :: struct {
	type_name:  base.Canonical_Name,
	trait_name: base.Canonical_Name,
	methods:    [dynamic]TIs_Method,
	span:       base.Source_Span,
}

TIs_Method :: struct {
	name:   base.Intern_ID,
	params: [dynamic]TFunc_Param,
	body:   TExpr,
	type_:  base.IR_Type,
	eff_:   base.IR_Type,
	is_pub: bool,
	span:   base.Source_Span,
}

TFile :: struct {
	path:    string,
	decls:   [dynamic]TDecl,
	imports: [dynamic]base.Deferred_Import,
	span:    base.Source_Span,
}

tfile_destroy :: proc(f: ^TFile) {
	if f == nil do return
	for decl in f.decls do tdecl_destroy(decl)
	delete(f.decls)
	// imports are shared with the canonical CFile — owned by cfile_destroy
	// TFile is stack-allocated in tests — no free(f)
}

tdecl_destroy :: proc(d: TDecl) {
	if d == nil do return
	#partial switch v in d {
	case ^TDecl_Const:
		texpr_destroy(v.body)
		delete(v.derive_targets)
		free(v)
	case ^TDecl_Effect:
		for op in v.operations do delete(op.params)
		delete(v.operations)
		for tp in v.type_params do delete(tp.constraints)
		delete(v.type_params)
		free(v)
	case ^TDecl_Trait:
		for m in v.methods do delete(m.params)
		delete(v.methods)
		free(v)
	case ^TDecl_Alias:
		free(v)
	case ^TDecl_Newtype:
		delete(v.type_params)
		delete(v.derive_targets)
		free(v)
	case ^TDecl_Import:
		delete(v.deferred.names)
		free(v)
	case ^TDecl_Test:
		texpr_destroy(v.body)
		free(v)
	case ^TDecl_Expect:
		texpr_destroy(v.condition)
		free(v)
	case ^TDecl_Is_Impl:
		for m in v.methods {
			delete(m.params)
			texpr_destroy(m.body)
		}
		delete(v.methods)
		free(v)
	case ^TDecl_Effect_Alias:
		free(v)
	}
}

texpr_destroy :: proc(e: TExpr) {
	if e == nil do return
	switch v in e {
	case ^TExpr_Int:
		free(v)
	case ^TExpr_Float:
		free(v)
	case ^TExpr_String:
		free(v)
	case ^TExpr_Bool:
		free(v)
	case ^TExpr_Char:
		free(v)
	case ^TExpr_Todo:
		texpr_destroy(v.message)
		free(v)
	case ^TExpr_Tag:
		for arg in v.payload do texpr_destroy(arg)
		delete(v.payload)
		free(v)
	case ^TExpr_Nominal_Construct:
		for arg in v.payload do texpr_destroy(arg)
		delete(v.payload)
		free(v)
	case ^TExpr_Record:
		for field in v.fields do texpr_destroy(field.value)
		delete(v.fields)
		texpr_destroy(v.rest)
		free(v)
	case ^TExpr_Tuple:
		for el in v.elements do texpr_destroy(el)
		delete(v.elements)
		free(v)
	case ^TExpr_List:
		for el in v.elements do texpr_destroy(el)
		delete(v.elements)
		texpr_destroy(v.rest)
		free(v)
	case ^TExpr_Name:
		free(v)
	case ^TExpr_Call:
		texpr_destroy(v.callee)
		for arg in v.args do texpr_destroy(arg)
		delete(v.args)
		free(v)
	case ^TExpr_Method_Call:
		texpr_destroy(v.receiver)
		for arg in v.args do texpr_destroy(arg)
		delete(v.args)
		free(v)
	case ^TExpr_Lambda:
		for tp in v.type_params do delete(tp.constraints)
		delete(v.type_params)
		delete(v.params)
		texpr_destroy(v.body)
		free(v)
	case ^TExpr_Block:
		for stmt in v.statements do texpr_destroy(stmt)
		delete(v.statements)
		free(v)
	case ^TExpr_If:
		texpr_destroy(v.condition)
		texpr_destroy(v.then_branch)
		texpr_destroy(v.else_branch)
		free(v)
	case ^TExpr_Match:
		texpr_destroy(v.scrutinee)
		for arm in v.arms {
			tpattern_destroy(arm.pattern)
			texpr_destroy(arm.guard)
			texpr_destroy(arm.body)
		}
		delete(v.arms)
		free(v)
	case ^TExpr_BinOp:
		texpr_destroy(v.left)
		texpr_destroy(v.right)
		free(v)
	case ^TExpr_PrefixOp:
		texpr_destroy(v.operand)
		free(v)
	case ^TExpr_Field_Access:
		texpr_destroy(v.record)
		free(v)
	case ^TExpr_Field_Index:
		texpr_destroy(v.record)
		free(v)
	case ^TExpr_Record_Update:
		texpr_destroy(v.rest)
		for update in v.updates do texpr_destroy(update.value)
		delete(v.updates)
		free(v)
	case ^TExpr_Assign:
		texpr_destroy(v.target)
		texpr_destroy(v.value)
		free(v)
	case ^TExpr_Return:
		texpr_destroy(v.value)
		free(v)
	case ^TExpr_Crash:
		texpr_destroy(v.message)
		free(v)
	case ^TExpr_Interpolated_String:
		for part in v.parts {
			switch p in part {
			case ^TExpr_String_Literal:
				free(p)
			case ^TExpr_String_Expr:
				texpr_destroy(p.expr)
				free(p)
			case TPattern:
				tpattern_destroy(p)
			}
		}
		delete(v.parts)
		free(v)
	case ^TExpr_Handle:
		delete(v.effects)
		texpr_destroy(v.body)
		for arm in v.arms {
			delete(arm.params)
			texpr_destroy(arm.body)
		}
		delete(v.arms)
		free(v)
	case ^TExpr_Perform:
		for arg in v.args do texpr_destroy(arg)
		delete(v.args)
		free(v)
	case ^TExpr_For:
		texpr_destroy(v.iterable)
		texpr_destroy(v.body)
		free(v)
	case ^TExpr_Par:
		delete(v.names)
		for expr in v.expressions do texpr_destroy(expr)
		delete(v.expressions)
		texpr_destroy(v.for_iter)
		texpr_destroy(v.for_body)
		free(v)
	}
}

tpattern_destroy :: proc(p: TPattern) {
	if p == nil do return
	switch v in p {
	case ^TPattern_Tag:
		for elem in v.payload do tpattern_destroy(elem)
		delete(v.payload)
		free(v)
	case ^TPattern_Record:
		delete(v.fields)
		free(v)
	case ^TPattern_Tuple:
		for elem in v.elements do tpattern_destroy(elem)
		delete(v.elements)
		free(v)
	case ^TPattern_List:
		for elem in v.elements do tpattern_destroy(elem)
		delete(v.elements)
		tpattern_destroy(v.rest)
		free(v)
	case ^TPattern_Int:
		free(v)
	case ^TPattern_String:
		free(v)
	case ^TPattern_Bool:
		free(v)
	case ^TPattern_Char:
		free(v)
	case ^TPattern_Identifier:
		free(v)
	case ^TPattern_Wildcard:
		free(v)
	case ^TPattern_Destructure:
		tpattern_destroy(v.inner)
		free(v)
	case ^TPattern_Or:
		for elem in v.alternatives do tpattern_destroy(elem)
		delete(v.alternatives)
		free(v)
	case ^TPattern_As:
		tpattern_destroy(v.inner)
		free(v)
	case ^TPattern_Interpolated_String:
		for part in v.parts {
			switch p in part {
			case ^TExpr_String_Literal:
				free(p)
			case ^TExpr_String_Expr:
				texpr_destroy(p.expr)
				free(p)
			case TPattern:
				tpattern_destroy(p)
			}
		}
		delete(v.parts)
		free(v)
	}
}

// resnapshot_decl_types walks a file's typed decls and re-derives every
// contained TExpr's type_ via resnapshot_texpr_types (camp-9xi6). Called once
// at the end of typecheck_file, after all unification has settled, so the
// propagated `closed` flag (and any other late type refinement) is reflected
// in the IR_Type snapshots that IR lowering copies into IR nodes.
resnapshot_decl_types :: proc(decls: []TDecl, store: ^Type_Store) {
	for d in decls {
		#partial switch v in d {
		case ^TDecl_Const:
			resnapshot_texpr_types(v.body, store)
			v.type_ = resnapshot_is_heap(store, v.type_)
		case ^TDecl_Test:
			resnapshot_texpr_types(v.body, store)
		case ^TDecl_Expect:
			resnapshot_texpr_types(v.condition, store)
		case ^TDecl_Is_Impl:
			for &m in v.methods {
				resnapshot_texpr_types(m.body, store)
				m.type_ = resnapshot_is_heap(store, m.type_)
			}
		case ^TDecl_Effect,
		     ^TDecl_Trait,
		     ^TDecl_Alias,
		     ^TDecl_Newtype,
		     ^TDecl_Import,
		     ^TDecl_Effect_Alias:
		// no TExpr body to resnapshot
		}
	}
}

// resnapshot_texpr_types walks a typed AST and updates ONLY the is_heap field
// of every TExpr's type_ when the underlying type is a tag union whose
// closedness was refined by late unification (camp-9xi6). Preserves wasm_type
// and type_id — changing those would alter wasm function signatures and break
// call_indirect dispatch (the parallel-map handler regression). Only tag-union
// rows are checked; all other inferred types have stable is_heap. Mirrors
// texpr_destroy's shape so every TExpr variant is covered.
// resnapshot_is_heap updates ONLY the is_heap field of an IR_Type snapshot by
// re-deriving it from the resolved type. This is the targeted version of the
// resnapshot: it only flips is_heap (the only field that can become stale due
// to late unification of tag-union closedness) and deliberately preserves the
// original wasm_type and type_id. Changing wasm_type (e.g. I64→Funcref for a
// now-resolved continuation type) would alter wasm function signatures and
// break call_indirect dispatch (the parallel-map regression). camp-9xi6.
resnapshot_is_heap :: proc(store: ^Type_Store, old: base.IR_Type) -> base.IR_Type {
	if old.type_id == base.Type_Var_ID(0) do return old
	resolved := resolve_var(store, old.type_id)
	v := &store.vars[int(resolved)]
	if inf, is_inf := v.link.(Inferred_Type); is_inf {
		if _, ok := inf.(Inferred_Tag_Union_Row); ok {
			new_is_heap := !tag_union_is_immediate(store, resolved)
			if old.is_heap != new_is_heap {
				return base.IR_Type {
					wasm_type = old.wasm_type,
					type_id = old.type_id,
					is_heap = new_is_heap,
				}
			}
		}
	}
	return old
}

resnapshot_texpr_types :: proc(expr: TExpr, store: ^Type_Store) {
	if expr == nil do return
	switch v in expr {
	case ^TExpr_Int:
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Float:
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_String:
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Bool:
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Char:
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Todo:
		resnapshot_texpr_types(v.message, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Tag:
		for arg in v.payload do resnapshot_texpr_types(arg, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Nominal_Construct:
		for arg in v.payload do resnapshot_texpr_types(arg, store)
	// resolved_type is a Type_ID (Type_Var_ID), not an IR_Type — no snapshot to refresh
	case ^TExpr_Record:
		for field in v.fields do resnapshot_texpr_types(field.value, store)
		resnapshot_texpr_types(v.rest, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Tuple:
		for el in v.elements do resnapshot_texpr_types(el, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_List:
		for el in v.elements do resnapshot_texpr_types(el, store)
		resnapshot_texpr_types(v.rest, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Name:
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Call:
		resnapshot_texpr_types(v.callee, store)
		for arg in v.args do resnapshot_texpr_types(arg, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Method_Call:
		resnapshot_texpr_types(v.receiver, store)
		for arg in v.args do resnapshot_texpr_types(arg, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Lambda:
		// params carry annotated types; body resnapshotted below.
		resnapshot_texpr_types(v.body, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Block:
		for stmt in v.statements do resnapshot_texpr_types(stmt, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_If:
		resnapshot_texpr_types(v.condition, store)
		resnapshot_texpr_types(v.then_branch, store)
		resnapshot_texpr_types(v.else_branch, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Match:
		resnapshot_texpr_types(v.scrutinee, store)
		for arm in v.arms {
			resnapshot_texpr_types(arm.guard, store)
			resnapshot_texpr_types(arm.body, store)
		}
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_BinOp:
		resnapshot_texpr_types(v.left, store)
		resnapshot_texpr_types(v.right, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_PrefixOp:
		resnapshot_texpr_types(v.operand, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Field_Access:
		resnapshot_texpr_types(v.record, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Field_Index:
		resnapshot_texpr_types(v.record, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Record_Update:
		resnapshot_texpr_types(v.rest, store)
		for update in v.updates do resnapshot_texpr_types(update.value, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Assign:
		resnapshot_texpr_types(v.target, store)
		resnapshot_texpr_types(v.value, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Return:
		resnapshot_texpr_types(v.value, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Crash:
		resnapshot_texpr_types(v.message, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Interpolated_String:
		for part in v.parts {
			switch p in part {
			case ^TExpr_String_Literal:
				p.type_ = resnapshot_is_heap(store, p.type_)
			case ^TExpr_String_Expr:
				resnapshot_texpr_types(p.expr, store)
			case TPattern:
			// patterns carry no IR_Type
			}
		}
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Handle:
		resnapshot_texpr_types(v.body, store)
		for arm in v.arms do resnapshot_texpr_types(arm.body, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Perform:
		for arg in v.args do resnapshot_texpr_types(arg, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_For:
		resnapshot_texpr_types(v.iterable, store)
		resnapshot_texpr_types(v.body, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	case ^TExpr_Par:
		for expr in v.expressions do resnapshot_texpr_types(expr, store)
		resnapshot_texpr_types(v.for_iter, store)
		resnapshot_texpr_types(v.for_body, store)
		v.type_ = resnapshot_is_heap(store, v.type_)
	}
}

