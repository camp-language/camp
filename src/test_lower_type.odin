package camp

import "camp:base"
import "camp:diagnostics"
import "camp:semantics"
import "core:testing"

@(test)
test_lower_type_i64 :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	i64_var := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ir := semantics.lower_type(&store, i64_var)

	testing.expect(t, ir.wasm_type == .I64)
	testing.expect(t, !ir.is_heap)
}

@(test)
test_lower_type_i32 :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i32_name := base.intern(store.interner, "I32")
	i32_var := semantics.make_primitive_type(&store, i32_name, base.Source_Span_ZERO)
	ir := semantics.lower_type(&store, i32_var)

	testing.expect(t, ir.wasm_type == .I32)
	testing.expect(t, !ir.is_heap)
}

@(test)
test_lower_type_f64 :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	f64_name := base.intern(store.interner, "F64")
	f64_var := semantics.make_primitive_type(&store, f64_name, base.Source_Span_ZERO)
	ir := semantics.lower_type(&store, f64_var)

	testing.expect(t, ir.wasm_type == .F64)
	testing.expect(t, !ir.is_heap)
}

@(test)
test_lower_type_f32 :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	f32_name := base.intern(store.interner, "F32")
	f32_var := semantics.make_primitive_type(&store, f32_name, base.Source_Span_ZERO)
	ir := semantics.lower_type(&store, f32_var)

	testing.expect(t, ir.wasm_type == .F32)
	testing.expect(t, !ir.is_heap)
}

@(test)
test_lower_type_bool :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	bool_name := base.intern(store.interner, "Bool")
	bool_var := semantics.make_primitive_type(&store, bool_name, base.Source_Span_ZERO)
	ir := semantics.lower_type(&store, bool_var)

	testing.expect(t, ir.wasm_type == .I32)
	testing.expect(t, !ir.is_heap)
}

@(test)
test_lower_type_str :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	str_name := base.intern(store.interner, "Str")
	str_var := semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)
	ir := semantics.lower_type(&store, str_var)

	testing.expect(t, ir.wasm_type == .I32)
	testing.expect(t, ir.is_heap)
}

@(test)
test_lower_type_unit :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	unit_name := base.intern(store.interner, "Unit")
	unit_var := semantics.make_primitive_type(&store, unit_name, base.Source_Span_ZERO)
	ir := semantics.lower_type(&store, unit_var)

	testing.expect(t, ir.wasm_type == .Void)
	testing.expect(t, !ir.is_heap)
}

@(test)
test_lower_type_function :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	i64_name := base.intern(store.interner, "I64")
	param := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	ret := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)
	eff := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)

	params := semantics.store_alloc(&store, base.Type_Var_ID, 1)
	params[0] = param

	fn_var := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		fn_var,
		semantics.Inferred_Function {
			param_ids = params,
			return_id = ret,
			effect_id = eff,
		},
	)

	ir := semantics.lower_type(&store, fn_var)
	testing.expect(t, ir.wasm_type == .Funcref)
	testing.expect(t, !ir.is_heap)
}

@(test)
test_lower_effect_type :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	console_name := base.intern(store.interner, "Console")
	eff_entries := semantics.store_alloc(&store, semantics.Effect_Row_Entry, 1)
	eff_entries[0] = semantics.Effect_Row_Entry {
		name      = console_name,
		type_args = {},
	}
	rest := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	eff_row := semantics.fresh_effect_row(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		eff_row,
		semantics.Inferred_Effect_Row { effects = eff_entries, rest_id = rest },
	)

	ir := semantics.lower_effect_type(&store, eff_row)
	testing.expect(t, ir.wasm_type == .Void)
}

@(test)
test_lower_type_newtype :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	uid_name := base.intern(store.interner, "UserId")
	i64_name := base.intern(store.interner, "I64")
	i64_var := semantics.make_primitive_type(&store, i64_name, base.Source_Span_ZERO)

	uid_var := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		uid_var,
		semantics.Inferred_Newtype {
			primitive_name = uid_name,
			arity          = 0,
			param_ids      = nil,
			inner_id       = i64_var,
		},
	)

	ir := semantics.lower_type(&store, uid_var)
	testing.expect(t, ir.wasm_type == .I64, "newtype I64 inner should propagate wasm_type")
	testing.expect(t, !ir.is_heap, "newtype I64 inner should propagate is_heap")
}

@(test)
test_lower_type_newtype_str_wrapper :: proc(t: ^testing.T) {
	store, collector := setup_type_store()
	defer teardown_type_store(&store, collector)

	label_name := base.intern(store.interner, "Label")
	str_name := base.intern(store.interner, "Str")
	str_var := semantics.make_primitive_type(&store, str_name, base.Source_Span_ZERO)

	label_var := semantics.fresh_value_var(&store, base.Source_Span_ZERO)
	semantics.link_var(
		&store,
		label_var,
		semantics.Inferred_Newtype {
			primitive_name = label_name,
			arity          = 0,
			param_ids      = nil,
			inner_id       = str_var,
		},
	)

	ir := semantics.lower_type(&store, label_var)
	testing.expect(t, ir.wasm_type == .I32, "newtype Str inner should propagate wasm_type .I32")
	testing.expect(t, ir.is_heap, "newtype Str inner should propagate is_heap true")
}
