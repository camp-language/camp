package semantics

import "core:mem"

import "camp:base"
import "camp:diagnostics"

Trait_Method_Info :: struct {
	name:        base.Intern_ID,
	param_types: []base.Type_Var_ID,
	return_type: base.Type_Var_ID,
}

Trait_Info :: struct {
	name:    base.Intern_ID,
	module:  base.Intern_ID,
	parent:  base.Intern_ID,
	methods: []Trait_Method_Info,
}

Trait_Impl :: struct {
	trait_name:  base.Intern_ID,
	type_name:   base.Intern_ID,
	type_module: base.Intern_ID,
	methods:     map[base.Intern_ID]base.Canonical_Name,
}

Type_Var_Kind :: enum {
	Value,
	Row_Record,
	Row_Tag,
	Row_Effect,
}

Type_Var :: struct {
	id:    base.Type_Var_ID,
	level: int,
	kind:  Type_Var_Kind,
	link:  Type_Link,
	name:  base.Intern_ID,
	span:  base.Source_Span,
}

Type_Link :: union {
	Type_Unlinked,
	base.Type_Var_ID,
	Inferred_Type,
}

Type_Unlinked :: struct {}

Type_Field_Entry :: struct {
	name: base.Intern_ID,
	var:  base.Type_Var_ID,
}

Type_Tag_Entry :: struct {
	name:    base.Intern_ID,
	payload: []base.Type_Var_ID,
}

Effect_Row_Entry :: struct {
	name:      base.Intern_ID,
	type_args: []base.Type_Var_ID, // empty for unparameterized effects
}

Inferred_Primitive :: struct {
	primitive_name: base.Intern_ID,
}

Inferred_Constructor :: struct {
	primitive_name: base.Intern_ID,
	arity:          int,
}

Inferred_Function :: struct {
	param_ids: []base.Type_Var_ID,
	return_id: base.Type_Var_ID,
	effect_id: base.Type_Var_ID,
}

Inferred_Newtype :: struct {
	primitive_name: base.Intern_ID,
	arity:          int,
	param_ids:      []base.Type_Var_ID,
	inner_id:       base.Type_Var_ID,
}

Inferred_Record_Row :: struct {
	record_fields: []Type_Field_Entry,
	record_rest:   base.Type_Var_ID,
	closed:        bool, // true = no additional fields allowed (type annotation context)
}

Inferred_Tag_Union_Row :: struct {
	tag_entries: []Type_Tag_Entry,
	tag_rest:    base.Type_Var_ID,
}

Inferred_Effect_Row :: struct {
	effects: []Effect_Row_Entry,
	rest_id: base.Type_Var_ID,
}

Inferred_Handle :: struct {
	inner_id:  base.Type_Var_ID,
	effect_id: base.Type_Var_ID,
}

Inferred_Type :: union {
	Inferred_Primitive,
	Inferred_Constructor,
	Inferred_Function,
	Inferred_Newtype,
	Inferred_Record_Row,
	Inferred_Tag_Union_Row,
	Inferred_Effect_Row,
	Inferred_Handle,
}

Newtype_Decl_Info :: struct {
	name:         base.Intern_ID,
	module:       base.Intern_ID,
	pub_variants: bool,
	type_params:  []base.Intern_ID,
	inner_type:   base.Type_Var_ID,
	owned_tags:   []base.Intern_ID,
}

Effect_Op_Sig :: struct {
	name:        base.Intern_ID,
	param_count: int,
	param_types: []base.Type_Var_ID,
	return_type: base.Type_Var_ID,
}

Type_Store :: struct {
	vars:                 [dynamic]Type_Var,
	next_id:              base.Type_Var_ID,
	current_level:        int,
	interner:             ^base.Intern_Table,
	collector:            ^diagnostics.Diagnostic_Collector,
	allocator:            mem.Allocator,
	declared_effects:     [dynamic]base.Intern_ID,
	bindings:             map[base.Intern_ID]base.Type_Var_ID,
	newtype_decls:        map[base.Intern_ID]Newtype_Decl_Info,
	trait_registry:       map[base.Intern_ID]Trait_Info,
	trait_impls:          [dynamic]Trait_Impl,
	type_constraints:     map[base.Type_Var_ID][]base.Intern_ID,
	rec_vars:             map[base.Type_Var_ID]bool,
	effect_ops:           map[base.Intern_ID][]Effect_Op_Sig,
	literal_int_values:   map[base.Type_Var_ID]i128,
	literal_float_values: map[base.Type_Var_ID]f64,
}

type_store_init :: proc(
	store: ^Type_Store,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
	allocator: mem.Allocator = context.allocator,
) {
	store.allocator = allocator
	store.vars = make([dynamic]Type_Var, 0, 256, allocator)
	store.next_id = 0
	store.current_level = base.LEVEL_TOP
	store.interner = interner
	store.collector = collector
	store.declared_effects = make([dynamic]base.Intern_ID, 0, 16, allocator)
	store.bindings = make(map[base.Intern_ID]base.Type_Var_ID, 64, allocator)
	store.newtype_decls = make(map[base.Intern_ID]Newtype_Decl_Info, 16, allocator)
	store.trait_registry = make(map[base.Intern_ID]Trait_Info, 16, allocator)
	store.trait_impls = make([dynamic]Trait_Impl, 0, 16, allocator)
	store.type_constraints = make(map[base.Type_Var_ID][]base.Intern_ID, 32, allocator)
	store.rec_vars = make(map[base.Type_Var_ID]bool, 4, allocator)
	store.effect_ops = make(map[base.Intern_ID][]Effect_Op_Sig, 16, allocator)
	store.literal_int_values = make(map[base.Type_Var_ID]i128, 16, allocator)
	store.literal_float_values = make(map[base.Type_Var_ID]f64, 16, allocator)
}

type_store_destroy :: proc(store: ^Type_Store) {
	for v in store.vars {
		inf, ok := v.link.(Inferred_Type)
		if !ok do continue
		switch f in inf {
		case Inferred_Function:
			if f.param_ids != nil do delete(f.param_ids, store.allocator)
		case Inferred_Newtype:
			if f.param_ids != nil do delete(f.param_ids, store.allocator)
		case Inferred_Record_Row:
			if f.record_fields != nil do delete(f.record_fields, store.allocator)
		case Inferred_Tag_Union_Row:
			if f.tag_entries != nil {
				for te in f.tag_entries {
					if te.payload != nil do delete(te.payload, store.allocator)
				}
				delete(f.tag_entries, store.allocator)
			}
		case Inferred_Effect_Row:
			if f.effects != nil {
				for e in f.effects {
					if e.type_args != nil do delete(e.type_args, store.allocator)
				}
				delete(f.effects, store.allocator)
			}
		case Inferred_Primitive, Inferred_Constructor, Inferred_Handle:
		}
	}
	for _, sigs in store.effect_ops {
		for sig in sigs {
			if len(sig.param_types) > 0 do delete(sig.param_types, store.allocator)
		}
		if len(sigs) > 0 do delete(sigs, store.allocator)
	}
	for _, constraints in store.type_constraints {
		if len(constraints) > 0 do delete(constraints, store.allocator)
	}
	for _, info in store.newtype_decls {
		if len(info.type_params) > 0 do delete(info.type_params, store.allocator)
		if len(info.owned_tags) > 0 do delete(info.owned_tags, store.allocator)
	}
	for _, info in store.trait_registry {
		if len(info.methods) > 0 do delete(info.methods, store.allocator)
	}
	delete(store.vars)
	delete(store.declared_effects)
	delete(store.bindings)
	delete(store.newtype_decls)
	delete(store.trait_registry)
	delete(store.trait_impls)
	delete(store.type_constraints)
	delete(store.rec_vars)
	delete(store.effect_ops)
	delete(store.literal_int_values)
	delete(store.literal_float_values)
}

fresh_var :: proc(
	store: ^Type_Store,
	kind: Type_Var_Kind,
	name: base.Intern_ID,
	span: base.Source_Span,
) -> base.Type_Var_ID {
	id := store.next_id
	store.next_id += 1
	v := Type_Var {
		id    = id,
		level = store.current_level,
		kind  = kind,
		link  = Type_Unlinked{},
		name  = name,
		span  = span,
	}
	append(&store.vars, v)
	return id
}

fresh_value_var :: proc(store: ^Type_Store, span: base.Source_Span) -> base.Type_Var_ID {
	return fresh_var(store, .Value, base.NO_NAME, span)
}

fresh_record_row :: proc(store: ^Type_Store, span: base.Source_Span) -> base.Type_Var_ID {
	return fresh_var(store, .Row_Record, base.NO_NAME, span)
}

fresh_tag_row :: proc(store: ^Type_Store, span: base.Source_Span) -> base.Type_Var_ID {
	return fresh_var(store, .Row_Tag, base.NO_NAME, span)
}

fresh_effect_row :: proc(store: ^Type_Store, span: base.Source_Span) -> base.Type_Var_ID {
	return fresh_var(store, .Row_Effect, base.NO_NAME, span)
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

	switch f in inf {
	case Inferred_Function:
		for pid in f.param_ids {
			child := store.vars[int(resolve_var(store, pid))]
			if child.level > max_level do return false
		}
		child_ret := store.vars[int(resolve_var(store, f.return_id))]
		if child_ret.level > max_level do return false
		child_eff := store.vars[int(resolve_var(store, f.effect_id))]
		if child_eff.level > max_level do return false

	case Inferred_Record_Row:
		for field in f.record_fields {
			child := store.vars[int(resolve_var(store, field.var))]
			if child.level > max_level do return false
		}
		child_rest := store.vars[int(resolve_var(store, f.record_rest))]
		if child_rest.level > max_level do return false

	case Inferred_Tag_Union_Row:
		for te in f.tag_entries {
			for pid in te.payload {
				child := store.vars[int(resolve_var(store, pid))]
				if child.level > max_level do return false
			}
		}
		child_rest := store.vars[int(resolve_var(store, f.tag_rest))]
		if child_rest.level > max_level do return false

	case Inferred_Effect_Row:
		child_rest := store.vars[int(resolve_var(store, f.rest_id))]
		if child_rest.level > max_level do return false

	case Inferred_Newtype:
		for pid in f.param_ids {
			child := store.vars[int(resolve_var(store, pid))]
			if child.level > max_level do return false
		}
		child_inner := store.vars[int(resolve_var(store, f.inner_id))]
		if child_inner.level > max_level do return false

	case Inferred_Handle:
		child_inner := store.vars[int(resolve_var(store, f.inner_id))]
		if child_inner.level > max_level do return false
		child_eff := store.vars[int(resolve_var(store, f.effect_id))]
		if child_eff.level > max_level do return false

	case Inferred_Primitive, Inferred_Constructor:
	}
	return true
}

generalize_at_level :: proc(store: ^Type_Store, level: int) {
	for i := 0; i < len(store.vars); i += 1 {
		v := &store.vars[i]
		if v.level == level && v.level != base.LEVEL_GENERIC {
			if all_children_at_or_below(store, v.link, level) {
				v.level = base.LEVEL_GENERIC
			}
		}
	}
}

is_generic :: proc(store: ^Type_Store, id: base.Type_Var_ID) -> bool {
	return store.vars[int(id)].level == base.LEVEL_GENERIC
}

link_var :: proc(store: ^Type_Store, id: base.Type_Var_ID, target: Type_Link) {
	store.vars[int(id)].link = target
}

resolve_var :: proc(store: ^Type_Store, id: base.Type_Var_ID) -> base.Type_Var_ID {
	v := &store.vars[int(id)]
	_, is_unlinked := v.link.(Type_Unlinked)
	if is_unlinked {
		return id
	}
	linked_id, is_id := v.link.(base.Type_Var_ID)
	if is_id {
		resolved := resolve_var(store, linked_id)
		if resolved != linked_id {
			v.link = resolved
		}
		return resolved
	}
	return id
}

make_primitive_type :: proc(
	store: ^Type_Store,
	name: base.Intern_ID,
	span: base.Source_Span,
) -> base.Type_Var_ID {
	var_id := fresh_value_var(store, span)
	store.vars[int(var_id)].link = Inferred_Primitive {
		primitive_name = name,
	}
	return var_id
}

store_alloc :: proc(store: ^Type_Store, $T: typeid, count: int) -> []T {
	return make([]T, count, store.allocator)
}

is_declared_effect :: proc(store: ^Type_Store, name: base.Intern_ID) -> bool {
	for ef in store.declared_effects {
		if ef == name {
			return true
		}
	}
	return false
}

is_declared_newtype :: proc(store: ^Type_Store, name: base.Intern_ID) -> bool {
	_, ok := store.newtype_decls[name]
	return ok
}

is_numeric_primitive :: proc(store: ^Type_Store, var_id: base.Type_Var_ID) -> bool {
	resolved := store.vars[int(resolve_var(store, var_id))]
	if inf, ok := resolved.link.(Inferred_Type); ok {
		if p, ok := inf.(Inferred_Primitive); ok {
			i64_name := base.intern(store.interner, "I64")
			i32_name := base.intern(store.interner, "I32")
			i16_name := base.intern(store.interner, "I16")
			i8_name := base.intern(store.interner, "I8")
			u64_name := base.intern(store.interner, "U64")
			u32_name := base.intern(store.interner, "U32")
			u16_name := base.intern(store.interner, "U16")
			u8_name := base.intern(store.interner, "U8")
			f64_name := base.intern(store.interner, "F64")
			f32_name := base.intern(store.interner, "F32")
			name := p.primitive_name
			return(
				name == i64_name ||
				name == i32_name ||
				name == i16_name ||
				name == i8_name ||
				name == u64_name ||
				name == u32_name ||
				name == u16_name ||
				name == u8_name ||
				name == f64_name ||
				name == f32_name \
			)
		}
	}
	return false
}

is_int_primitive_name :: proc(store: ^Type_Store, name: base.Intern_ID) -> bool {
	i64_name := base.intern(store.interner, "I64")
	i32_name := base.intern(store.interner, "I32")
	i16_name := base.intern(store.interner, "I16")
	i8_name := base.intern(store.interner, "I8")
	u64_name := base.intern(store.interner, "U64")
	u32_name := base.intern(store.interner, "U32")
	u16_name := base.intern(store.interner, "U16")
	u8_name := base.intern(store.interner, "U8")
	return(
		name == i64_name ||
		name == i32_name ||
		name == i16_name ||
		name == i8_name ||
		name == u64_name ||
		name == u32_name ||
		name == u16_name ||
		name == u8_name \
	)
}

is_float_primitive_name :: proc(store: ^Type_Store, name: base.Intern_ID) -> bool {
	f64_name := base.intern(store.interner, "F64")
	f32_name := base.intern(store.interner, "F32")
	return name == f64_name || name == f32_name
}

int_fits_type :: proc(value: i128, type_name: string) -> bool {
	switch type_name {
	case "I8":
		return value >= -128 && value <= 127
	case "I16":
		return value >= -32768 && value <= 32767
	case "I32":
		return value >= -2147483648 && value <= 2147483647
	case "I64":
		return value >= -9223372036854775808 && value <= 9223372036854775807
	case "U8":
		return value >= 0 && value <= 255
	case "U16":
		return value >= 0 && value <= 65535
	case "U32":
		return value >= 0 && value <= 4294967295
	case "U64":
		return value >= 0 && value <= 18446744073709551615
	case:
		return false
	}
}

float_fits_type :: proc(value: f64, type_name: string) -> bool {
	switch type_name {
	case "F32":
		return f64(f32(value)) == value
	case "F64":
		return true
	case:
		return false
	}
}

is_trait_declared :: proc(store: ^Type_Store, name: base.Intern_ID) -> bool {
	_, ok := store.trait_registry[name]
	return ok
}

find_trait_impl :: proc(
	store: ^Type_Store,
	trait_name: base.Intern_ID,
	type_name: base.Intern_ID,
) -> (
	Trait_Impl,
	bool,
) {
	for impl in store.trait_impls {
		if impl.trait_name == trait_name && impl.type_name == type_name {
			return impl, true
		}
	}
	return Trait_Impl{}, false
}

implements_display :: proc(store: ^Type_Store, type_name: base.Intern_ID) -> bool {
	display_name := base.intern(store.interner, "Display")
	_, found := find_trait_impl(store, display_name, type_name)
	return found
}

find_trait_impl_by_method :: proc(
	store: ^Type_Store,
	type_name: base.Intern_ID,
	method_name: base.Intern_ID,
) -> (
	Trait_Impl,
	bool,
) {
	for impl in store.trait_impls {
		if impl.type_name == type_name {
			if _, has := impl.methods[method_name]; has {
				return impl, true
			}
		}
	}
	return Trait_Impl{}, false
}

collect_all_traits :: proc(
	trait_name: base.Intern_ID,
	registry: map[base.Intern_ID]Trait_Info,
) -> []base.Intern_ID {
	visited := make(map[base.Intern_ID]bool)
	result := make([dynamic]base.Intern_ID, 0, 8)
	worklist := make([dynamic]base.Intern_ID, 0, 8)
	append(&worklist, trait_name)
	for len(worklist) > 0 {
		current := pop(&worklist)
		if visited[current] {
			continue
		}
		visited[current] = true
		append(&result, current)
		if info, ok := registry[current]; ok && info.parent != base.NO_NAME {
			append(&worklist, info.parent)
		}
	}
	delete(visited)
	delete(worklist)
	return result[:]
}

