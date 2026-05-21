package camp

Type_Var_ID :: distinct int

LEVEL_GENERIC :: -1
LEVEL_TOP :: 0

Trait_Method_Info :: struct {
	name:        Intern_ID,
	param_types: []Type_Var_ID,
	return_type: Type_Var_ID,
}

Trait_Info :: struct {
	name:    Intern_ID,
	module:  Intern_ID,
	parent:  Intern_ID,
	methods: []Trait_Method_Info,
}

Trait_Impl :: struct {
	trait_name:  Intern_ID,
	type_name:   Intern_ID,
	type_module: Intern_ID,
	methods:     map[Intern_ID]Canonical_Name,
}

Type_Var_Kind :: enum {
	Value,
	Row_Record,
	Row_Tag,
	Row_Effect,
}

Type_Var :: struct {
	id:    Type_Var_ID,
	level: int,
	kind:  Type_Var_Kind,
	link:  Type_Link,
	name:  Intern_ID,
	span:  Source_Span,
}

Type_Link :: union {
	Type_Unlinked,
	Type_Var_ID,
	Inferred_Type,
}

Type_Unlinked :: struct {}

Inferred_Tag :: enum {
	Primitive,
	Constructor,
	Newtype,
	Function,
	Record_Row,
	Tag_Union_Row,
	Effect_Row,
}

Type_Field_Entry :: struct {
	name: Intern_ID,
	var:  Type_Var_ID,
}

Type_Tag_Entry :: struct {
	name:    Intern_ID,
	payload: []Type_Var_ID,
}

Inferred_Type :: struct {
	tag:            Inferred_Tag,
	primitive_name: Intern_ID,
	arity:          int,

	param_ids:  []Type_Var_ID,
	return_id:  Type_Var_ID,
	effect_id:  Type_Var_ID,

	inner_id: Type_Var_ID,

	effect_names: []Intern_ID,
	rest_id:      Type_Var_ID,

	record_fields: []Type_Field_Entry,
	record_rest:   Type_Var_ID,

	tag_entries: []Type_Tag_Entry,
	tag_rest:    Type_Var_ID,
}

Newtype_Decl_Info :: struct {
	name:        Intern_ID,
	type_params: []Intern_ID,
	inner_type:  Type_Var_ID,
	owned_tags:  []Intern_ID,
}

Type_Store :: struct {
	vars:             [dynamic]Type_Var,
	next_id:          Type_Var_ID,
	current_level:    int,
	interner:         ^Intern_Table,
	collector:        ^Diagnostic_Collector,
	declared_effects: [dynamic]Intern_ID,
	bindings:         map[Intern_ID]Type_Var_ID,
	newtype_decls:    map[Intern_ID]Newtype_Decl_Info,
	trait_registry:   map[Intern_ID]Trait_Info,
	trait_impls:      [dynamic]Trait_Impl,
	type_constraints:  map[Type_Var_ID][]Intern_ID,
}

type_store_init :: proc(store: ^Type_Store, interner: ^Intern_Table, collector: ^Diagnostic_Collector) {
	store.vars = make([dynamic]Type_Var, 0, 256)
	store.next_id = 0
	store.current_level = LEVEL_TOP
	store.interner = interner
	store.collector = collector
	store.declared_effects = make([dynamic]Intern_ID, 0, 16)
	store.bindings = make(map[Intern_ID]Type_Var_ID, 64)
	store.newtype_decls = make(map[Intern_ID]Newtype_Decl_Info, 16)
	store.trait_registry = make(map[Intern_ID]Trait_Info, 16)
	store.trait_impls = make([dynamic]Trait_Impl, 0, 16)
	store.type_constraints = make(map[Type_Var_ID][]Intern_ID, 32)
}

type_store_destroy :: proc(store: ^Type_Store) {
	delete(store.vars)
	delete(store.declared_effects)
	delete(store.bindings)
	delete(store.newtype_decls)
	delete(store.trait_registry)
	delete(store.trait_impls)
	delete(store.type_constraints)
}

fresh_var :: proc(store: ^Type_Store, kind: Type_Var_Kind, name: Intern_ID, span: Source_Span) -> Type_Var_ID {
	id := store.next_id
	store.next_id += 1
	v := Type_Var{
		id = id,
		level = store.current_level,
		kind = kind,
		link = Type_Unlinked{},
		name = name,
		span = span,
	}
	append(&store.vars, v)
	return id
}

fresh_value_var :: proc(store: ^Type_Store, span: Source_Span) -> Type_Var_ID {
	return fresh_var(store, .Value, NO_NAME, span)
}

fresh_record_row :: proc(store: ^Type_Store, span: Source_Span) -> Type_Var_ID {
	return fresh_var(store, .Row_Record, NO_NAME, span)
}

fresh_tag_row :: proc(store: ^Type_Store, span: Source_Span) -> Type_Var_ID {
	return fresh_var(store, .Row_Tag, NO_NAME, span)
}

fresh_effect_row :: proc(store: ^Type_Store, span: Source_Span) -> Type_Var_ID {
	return fresh_var(store, .Row_Effect, NO_NAME, span)
}

enter_level :: proc(store: ^Type_Store) {
	store.current_level += 1
}

exit_level :: proc(store: ^Type_Store) {
	store.current_level -= 1
}

all_children_at_or_below :: proc(store: ^Type_Store, link: Type_Link, max_level: int) -> bool {
	_, is_unlinked := link.(Type_Unlinked)
	if is_unlinked do return true

	inf, is_inferred := link.(Inferred_Type)
	if !is_inferred do return true

	#partial switch inf.tag {
	case .Function:
		for pid in inf.param_ids {
			child := get_var(store, resolve_var(store, pid))
			if child.level > max_level do return false
		}
		child_ret := get_var(store, resolve_var(store, inf.return_id))
		if child_ret.level > max_level do return false
		child_eff := get_var(store, resolve_var(store, inf.effect_id))
		if child_eff.level > max_level do return false

	case .Record_Row:
		for f in inf.record_fields {
			child := get_var(store, resolve_var(store, f.var))
			if child.level > max_level do return false
		}
		child_rest := get_var(store, resolve_var(store, inf.record_rest))
		if child_rest.level > max_level do return false

	case .Tag_Union_Row:
		for te in inf.tag_entries {
			for pid in te.payload {
				child := get_var(store, resolve_var(store, pid))
				if child.level > max_level do return false
			}
		}
		child_rest := get_var(store, resolve_var(store, inf.tag_rest))
		if child_rest.level > max_level do return false

	case .Effect_Row:
		child_rest := get_var(store, resolve_var(store, inf.rest_id))
		if child_rest.level > max_level do return false

	case .Newtype:
		for pid in inf.param_ids {
			child := get_var(store, resolve_var(store, pid))
			if child.level > max_level do return false
		}
		child_inner := get_var(store, resolve_var(store, inf.inner_id))
		if child_inner.level > max_level do return false

	case .Primitive, .Constructor:
	}
	return true
}

generalize_at_level :: proc(store: ^Type_Store, level: int) {
	for i := 0; i < len(store.vars); i += 1 {
		v := &store.vars[i]
		if v.level == level && v.level != LEVEL_GENERIC {
			if all_children_at_or_below(store, v.link, level) {
				v.level = LEVEL_GENERIC
			}
		}
	}
}

get_var :: proc(store: ^Type_Store, id: Type_Var_ID) -> ^Type_Var {
	return &store.vars[int(id)]
}

is_generic :: proc(store: ^Type_Store, id: Type_Var_ID) -> bool {
	return store.vars[int(id)].level == LEVEL_GENERIC
}

link_var :: proc(store: ^Type_Store, id: Type_Var_ID, target: Type_Link) {
	store.vars[int(id)].link = target
}

resolve_var :: proc(store: ^Type_Store, id: Type_Var_ID) -> Type_Var_ID {
	v := get_var(store, id)
	_, is_unlinked := v.link.(Type_Unlinked)
	if is_unlinked {
		return id
	}
	linked_id, is_id := v.link.(Type_Var_ID)
	if is_id {
		resolved := resolve_var(store, linked_id)
		if resolved != linked_id {
			v.link = resolved
		}
		return resolved
	}
	return id
}

make_primitive_type :: proc(store: ^Type_Store, name: Intern_ID, span: Source_Span) -> Type_Var_ID {
	var_id := fresh_value_var(store, span)
	v := get_var(store, var_id)
	v.link = Inferred_Type{tag = .Primitive, primitive_name = name}
	return var_id
}

store_alloc :: proc(store: ^Type_Store, $T: typeid, count: int) -> []T {
	return make([]T, count)
}

is_declared_effect :: proc(store: ^Type_Store, name: Intern_ID) -> bool {
	for ef in store.declared_effects {
		if ef == name {
			return true
		}
	}
	return false
}

is_declared_newtype :: proc(store: ^Type_Store, name: Intern_ID) -> bool {
	_, ok := store.newtype_decls[name]
	return ok
}

is_numeric_primitive :: proc(store: ^Type_Store, var_id: Type_Var_ID) -> bool {
	resolved := get_var(store, resolve_var(store, var_id))
	if inf, ok := resolved.link.(Inferred_Type); ok && inf.tag == .Primitive {
		i64_name := intern(store.interner, "I64")
		i32_name := intern(store.interner, "I32")
		u64_name := intern(store.interner, "U64")
		f64_name := intern(store.interner, "F64")
		f32_name := intern(store.interner, "F32")
		return inf.primitive_name == i64_name ||
			inf.primitive_name == i32_name ||
			inf.primitive_name == u64_name ||
			inf.primitive_name == f64_name ||
			inf.primitive_name == f32_name
	}
	return false
}

is_trait_declared :: proc(store: ^Type_Store, name: Intern_ID) -> bool {
	_, ok := store.trait_registry[name]
	return ok
}

find_trait_impl :: proc(store: ^Type_Store, trait_name: Intern_ID, type_name: Intern_ID) -> (Trait_Impl, bool) {
	for impl in store.trait_impls {
		if impl.trait_name == trait_name && impl.type_name == type_name {
			return impl, true
		}
	}
	return Trait_Impl{}, false
}

find_trait_impl_by_method :: proc(store: ^Type_Store, type_name: Intern_ID, method_name: Intern_ID) -> (Trait_Impl, bool) {
	for impl in store.trait_impls {
		if impl.type_name == type_name {
			if _, has := impl.methods[method_name]; has {
				return impl, true
			}
		}
	}
	return Trait_Impl{}, false
}

collect_all_traits :: proc(trait_name: Intern_ID, registry: map[Intern_ID]Trait_Info) -> []Intern_ID {
	visited := make(map[Intern_ID]bool)
	result := make([dynamic]Intern_ID, 0, 8)
	worklist := make([dynamic]Intern_ID, 0, 8)
	append(&worklist, trait_name)
	for len(worklist) > 0 {
		current := pop(&worklist)
		if visited[current] {
			continue
		}
		visited[current] = true
		append(&result, current)
		if info, ok := registry[current]; ok && info.parent != NO_NAME {
			append(&worklist, info.parent)
		}
	}
	delete(visited)
	delete(worklist)
	return result[:]
}
