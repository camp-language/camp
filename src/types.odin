package camp

Type_Var_ID :: distinct int

LEVEL_GENERIC :: -1
LEVEL_TOP :: 0

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

	effect_names: []Intern_ID,
	rest_id:      Type_Var_ID,

	record_fields: []Type_Field_Entry,
	record_rest:   Type_Var_ID,

	tag_entries: []Type_Tag_Entry,
	tag_rest:    Type_Var_ID,
}

Type_Store :: struct {
	vars:            [dynamic]Type_Var,
	next_id:         Type_Var_ID,
	current_level:   int,
	interner:        ^Intern_Table,
	collector:       ^Diagnostic_Collector,
	declared_effects: [dynamic]Intern_ID,
}

type_store_init :: proc(store: ^Type_Store, interner: ^Intern_Table, collector: ^Diagnostic_Collector) {
	store.vars = make([dynamic]Type_Var, 0, 256)
	store.next_id = 0
	store.current_level = LEVEL_TOP
	store.interner = interner
	store.collector = collector
	store.declared_effects = make([dynamic]Intern_ID, 0, 16)
}

type_store_destroy :: proc(store: ^Type_Store) {
	delete(store.vars)
	delete(store.declared_effects)
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

generalize_at_level :: proc(store: ^Type_Store, level: int) {
	for i := 0; i < len(store.vars); i += 1 {
		if store.vars[i].level == level && store.vars[i].level != LEVEL_GENERIC {
			store.vars[i].level = LEVEL_GENERIC
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
