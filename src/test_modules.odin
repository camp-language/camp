package camp

import "camp:base"
import "camp:build"
import "camp:semantics"
import "camp:diagnostics"
import "core:strings"
import "core:testing"

@(test)
test_path_to_module_name_top :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	id := build.path_to_module_name("src/List.camp", "src", &ctx.interner)
	name := base.intern_get(&ctx.interner, id)
	testing.expect(t, name == "List")
}

@(test)
test_path_to_module_name_nested :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	id := build.path_to_module_name("src/Http/Server.camp", "src", &ctx.interner)
	name := base.intern_get(&ctx.interner, id)
	testing.expect(t, name == "Http.Server")
}

@(test)
test_path_to_module_name_deep :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	id := build.path_to_module_name("src/A/B/C.camp", "src", &ctx.interner)
	name := base.intern_get(&ctx.interner, id)
	testing.expect(t, name == "A.B.C")
}

@(test)
test_simple_hash_deterministic :: proc(t: ^testing.T) {
	a := build.simple_hash("hello")
	b := build.simple_hash("hello")
	testing.expect(t, a == b)
}

@(test)
test_simple_hash_different_inputs :: proc(t: ^testing.T) {
	a := build.simple_hash("hello")
	b := build.simple_hash("world")
	testing.expect(t, a != b)
}

@(test)
test_mangle_name_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	mod := base.intern(&ctx.interner, "List")
	name := base.intern(&ctx.interner, "map")
	result := base.mangle_name(mod, name, &ctx.interner)
	testing.expect(t, result == "List__map")
}

@(test)
test_mangle_name_nested :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	mod := base.intern(&ctx.interner, "Http.Server")
	name := base.intern(&ctx.interner, "handle")
	result := base.mangle_name(mod, name, &ctx.interner)
	testing.expect(t, result == "Http_Server__handle")
}

@(test)
test_export_table_manual :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	et: build.Export_Table
	build.export_table_init(&et)
	defer build.export_table_destroy(&et)

	x_name := base.intern(&ctx.interner, "x")
	et.exports[x_name] = build.Export_Info{
		name = x_name,
		kind = .Const,
		is_pub = true,
		type_var = base.Type_Var_ID(-1),
	}

	ei, ok := build.export_lookup(&et, x_name)
	testing.expect(t, ok)
	testing.expect(t, ei.is_pub)

	y_name := base.intern(&ctx.interner, "y")
	_, y_ok := build.export_lookup(&et, y_name)
	testing.expect(t, !y_ok)
}

@(test)
test_module_graph_topo_sort :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	graph: build.Module_Graph
	build.module_graph_init(&graph)
	defer build.module_graph_destroy(&graph)

	a := base.intern(&ctx.interner, "A")
	b := base.intern(&ctx.interner, "B")
	c := base.intern(&ctx.interner, "C")

	build.module_graph_add_node(&graph, a)
	build.module_graph_add_node(&graph, b)
	build.module_graph_add_node(&graph, c)
	build.module_graph_add_edge(&graph, a, b)
	build.module_graph_add_edge(&graph, b, c)

	sorted, ok := build.topological_sort(&graph, &ctx.interner, &ctx.collector)
	testing.expect(t, ok)

	if ok && len(sorted) == 3 {
		a_idx := -1
		b_idx := -1
		c_idx := -1
		for i: int = 0; i < len(sorted); i += 1 {
			id := sorted[i]
			if id == a do a_idx = i
			if id == b do b_idx = i
			if id == c do c_idx = i
		}
		testing.expect(t, a_idx < b_idx)
		testing.expect(t, b_idx < c_idx)
	}
}

@(test)
test_module_graph_cycle_detection :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	graph: build.Module_Graph
	build.module_graph_init(&graph)
	defer build.module_graph_destroy(&graph)

	a := base.intern(&ctx.interner, "A")
	b := base.intern(&ctx.interner, "B")

	build.module_graph_add_node(&graph, a)
	build.module_graph_add_node(&graph, b)
	build.module_graph_add_edge(&graph, a, b)
	build.module_graph_add_edge(&graph, b, a)

	_, ok := build.topological_sort(&graph, &ctx.interner, &ctx.collector)
	testing.expect(t, !ok)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_module_graph_independent :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	graph: build.Module_Graph
	build.module_graph_init(&graph)
	defer build.module_graph_destroy(&graph)

	a := base.intern(&ctx.interner, "A")
	b := base.intern(&ctx.interner, "B")

	build.module_graph_add_node(&graph, a)
	build.module_graph_add_node(&graph, b)

	sorted, ok := build.topological_sort(&graph, &ctx.interner, &ctx.collector)
	testing.expect(t, ok)
	testing.expect(t, len(sorted) == 2)
}

@(test)
test_inject_prelude_types :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)

	bool_name := base.intern(&ctx.interner, "Bool")
	_, bool_ok := store.bindings[bool_name]
	testing.expect(t, bool_ok)

	i64_name := base.intern(&ctx.interner, "I64")
	_, i64_ok := store.bindings[i64_name]
	testing.expect(t, i64_ok)

	str_name := base.intern(&ctx.interner, "Str")
	_, str_ok := store.bindings[str_name]
	testing.expect(t, str_ok)

	true_name := base.intern(&ctx.interner, "True")
	_, true_ok := store.bindings[true_name]
	testing.expect(t, true_ok)

	false_name := base.intern(&ctx.interner, "False")
	_, false_ok := store.bindings[false_name]
	testing.expect(t, false_ok)
}

@(test)
test_import_scope_local_names :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	scope: build.Import_Scope
	build.import_scope_init(&scope)
	defer build.import_scope_destroy(&scope)

	x_name := base.intern(&ctx.interner, "x")
	scope.unqualified[x_name] = base.Canonical_Name{module = base.NO_NAME, name = x_name, is_local = true}

	resolved, ok := build.resolve_name(x_name, &scope, &ctx.interner)
	testing.expect(t, ok)
	testing.expect(t, resolved.is_local == true)
}

@(test)
test_import_scope_missing :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	scope: build.Import_Scope
	build.import_scope_init(&scope)
	defer build.import_scope_destroy(&scope)

	x_name := base.intern(&ctx.interner, "x")
	_, ok := build.resolve_name(x_name, &scope, &ctx.interner)
	testing.expect(t, !ok)
}

@(test)
test_cache_key_for_typecheck :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	project: build.Project_Discovery
	project.modules = make(map[base.Intern_ID]build.Module_Info, 4)
	project.module_names = make([dynamic]base.Intern_ID, 0, 4)

	a_name := base.intern(&ctx.interner, "A")
	b_name := base.intern(&ctx.interner, "B")

	project.modules[a_name] = build.Module_Info{
		name = a_name,
		content_hash = "hash_a",
		imports = make([dynamic]base.Deferred_Import, 0, 4),
		exports = make([dynamic]build.Export_Info, 0, 4),
	}
	project.modules[b_name] = build.Module_Info{
		name = b_name,
		content_hash = "hash_b",
		imports = make([dynamic]base.Deferred_Import, 0, 4),
		exports = make([dynamic]build.Export_Info, 0, 4),
	}

	mi := project.modules[a_name]
	imp: base.Deferred_Import
	imp.module = b_name
	append(&mi.imports, imp)
	project.modules[a_name] = mi

	key := build.cache_key_for_typecheck(&project.modules[a_name], &project, &ctx.interner)
	testing.expect(t, len(key) > 0)

	build.project_discovery_destroy(&project)
}

@(test)
test_module_graph_three_node_cycle :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	graph: build.Module_Graph
	build.module_graph_init(&graph)
	defer build.module_graph_destroy(&graph)

	a := base.intern(&ctx.interner, "A")
	b := base.intern(&ctx.interner, "B")
	c := base.intern(&ctx.interner, "C")

	build.module_graph_add_node(&graph, a)
	build.module_graph_add_node(&graph, b)
	build.module_graph_add_node(&graph, c)
	build.module_graph_add_edge(&graph, a, b)
	build.module_graph_add_edge(&graph, b, c)
	build.module_graph_add_edge(&graph, c, a)

	_, ok := build.topological_sort(&graph, &ctx.interner, &ctx.collector)
	testing.expect(t, !ok)
	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_duplicate_name_const_and_effect :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	scope: semantics.Canonicalize_Scope
	scope.local_names = make(map[base.Intern_ID]base.Canonical_Name, 8)
	scope.local_kinds = make(map[base.Intern_ID]semantics.Decl_Kind, 8)
	defer delete(scope.local_names)
	defer delete(scope.local_kinds)

	x_name := base.intern(&ctx.interner, "Result")
	_ = semantics.canonicalize_local_name(x_name, .Const, &scope, &ctx.interner, &ctx.collector)
	_ = semantics.canonicalize_local_name(x_name, .Effect, &scope, &ctx.interner, &ctx.collector)

	testing.expect(t, diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_duplicate_name_same_kind_ok :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	scope: semantics.Canonicalize_Scope
	scope.local_names = make(map[base.Intern_ID]base.Canonical_Name, 8)
	scope.local_kinds = make(map[base.Intern_ID]semantics.Decl_Kind, 8)
	defer delete(scope.local_names)
	defer delete(scope.local_kinds)

	x_name := base.intern(&ctx.interner, "map")
	_ = semantics.canonicalize_local_name(x_name, .Const, &scope, &ctx.interner, &ctx.collector)
	_ = semantics.canonicalize_local_name(x_name, .Const, &scope, &ctx.interner, &ctx.collector)

	testing.expect(t, !diagnostics.diag_collector_has_errors(&ctx.collector))
}

@(test)
test_manifest_round_trip :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	manifest: build.Module_Manifest
	manifest.content_hash = "abc123"
	manifest.module_name = "List"
	manifest.imports = make([dynamic]build.Manifest_Import, 0, 4)
	manifest.exports = make([dynamic]build.Manifest_Export, 0, 4)

	imp: build.Manifest_Import
	imp.module = "Maybe"
	imp.names = make([dynamic]string, 0, 4)
	append(&imp.names, "just")
	append(&imp.names, "nothing")
	imp.alias = ""
	append(&manifest.imports, imp)

	exp: build.Manifest_Export
	exp.name = "map"
	exp.kind = .Const
	exp.is_pub = true
	exp.pub_variants = false
	append(&manifest.exports, exp)

	nt_exp: build.Manifest_Export
	nt_exp.name = "Result"
	nt_exp.kind = .Newtype
	nt_exp.is_pub = true
	nt_exp.pub_variants = true
	append(&manifest.exports, nt_exp)

	data := build.serialize_manifest(manifest, ctx.allocator)
	testing.expect(t, len(data) > 0)

	result, ok := build.deserialize_manifest(data, ctx.allocator)
	testing.expect(t, ok)
	testing.expect(t, result.content_hash == "abc123")
	testing.expect(t, result.module_name == "List")
	testing.expect(t, len(result.imports) == 1)
	testing.expect(t, len(result.exports) == 2)

	if len(result.imports) > 0 {
		testing.expect(t, result.imports[0].module == "Maybe")
		testing.expect(t, len(result.imports[0].names) == 2)
		testing.expect(t, result.imports[0].names[0] == "just")
	}

	if len(result.exports) > 0 {
		testing.expect(t, result.exports[0].name == "map")
		testing.expect(t, result.exports[0].kind == .Const)
		testing.expect(t, result.exports[0].is_pub == true)
		testing.expect(t, result.exports[0].pub_variants == false)
	}

	if len(result.exports) > 1 {
		testing.expect(t, result.exports[1].name == "Result")
		testing.expect(t, result.exports[1].kind == .Newtype)
		testing.expect(t, result.exports[1].is_pub == true)
		testing.expect(t, result.exports[1].pub_variants == true)
	}

	build.manifest_destroy(&manifest)
	build.manifest_destroy(&result)
}

@(test)
test_manifest_deserialize_bad_magic :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	data := []byte{0xDE, 0xAD, 0xBE, 0xEF, 0, 0, 0, 0}
	_, ok := build.deserialize_manifest(data, ctx.allocator)
	testing.expect(t, !ok)
}

@(test)
test_cache_has_miss :: proc(t: ^testing.T) {
	has := build.cache_has("nonexistent_key_12345", ".manifest")
	testing.expect(t, !has)
}

@(test)
test_export_table_newtype_pub :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)

	result_name := base.intern(&ctx.interner, "Result")
	nt := semantics.CDecl_Newtype{
		name = base.Canonical_Name{name = result_name, is_local = true},
		is_pub = true,
		pub_variants = true,
	}

	cfile: semantics.CFile
	cfile.decls = make([dynamic]semantics.CDecl, 1)
	append(&cfile.decls, semantics.CDecl(&nt))

	et := build.collect_exports(cfile, &store)
	defer build.export_table_destroy(&et)

	ei, ok := build.export_lookup(&et, result_name)
	testing.expect(t, ok)
	testing.expect(t, ei.kind == .Newtype)
	testing.expect(t, ei.is_pub)
	testing.expect(t, ei.pub_variants)
}

@(test)
test_export_table_newtype_private :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)

	result_name := base.intern(&ctx.interner, "Result")
	nt := semantics.CDecl_Newtype{
		name = base.Canonical_Name{name = result_name, is_local = true},
		is_pub = false,
		pub_variants = false,
	}

	cfile: semantics.CFile
	cfile.decls = make([dynamic]semantics.CDecl, 1)
	append(&cfile.decls, semantics.CDecl(&nt))

	et := build.collect_exports(cfile, &store)
	defer build.export_table_destroy(&et)

	_, ok := build.export_lookup(&et, result_name)
	testing.expect(t, !ok)
}

@(test)
test_export_table_newtype_pub_opaque :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	defer semantics.type_store_destroy(&store)

	userid_name := base.intern(&ctx.interner, "UserId")
	nt := semantics.CDecl_Newtype{
		name = base.Canonical_Name{name = userid_name, is_local = true},
		is_pub = true,
		pub_variants = false,
	}

	cfile: semantics.CFile
	cfile.decls = make([dynamic]semantics.CDecl, 1)
	append(&cfile.decls, semantics.CDecl(&nt))

	et := build.collect_exports(cfile, &store)
	defer build.export_table_destroy(&et)

	ei, ok := build.export_lookup(&et, userid_name)
	testing.expect(t, ok)
	testing.expect(t, ei.kind == .Newtype)
	testing.expect(t, ei.is_pub)
	testing.expect(t, !ei.pub_variants)
}

@(test)
test_register_stdlib_modules_populates_project :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	project: build.Project_Discovery
	project.modules = make(map[base.Intern_ID]build.Module_Info, 8)
	project.module_names = make([dynamic]base.Intern_ID, 0, 8)

	build.register_stdlib_modules(&project, &ctx.interner)
	defer build.project_discovery_destroy(&project)

	testing.expect(t, len(project.modules) > 0)
	testing.expect(t, len(project.module_names) > 0)

	result_name := base.intern(&ctx.interner, "Result")
	_, result_ok := project.modules[result_name]
	testing.expect(t, result_ok, "Result module should be registered")

	bool_name := base.intern(&ctx.interner, "Bool")
	_, bool_ok := project.modules[bool_name]
	testing.expect(t, bool_ok, "Bool module should be registered")
}

@(test)
test_register_stdlib_modules_source_populated :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	project: build.Project_Discovery
	project.modules = make(map[base.Intern_ID]build.Module_Info, 8)
	project.module_names = make([dynamic]base.Intern_ID, 0, 8)

	build.register_stdlib_modules(&project, &ctx.interner)
	defer build.project_discovery_destroy(&project)

	result_name := base.intern(&ctx.interner, "Result")
	mi := project.modules[result_name]

	testing.expect(t, len(mi.source) > 0, "Result module source should be non-empty")
	testing.expect(t, strings.contains(mi.source, "@Result"), "Result module source should contain @Result", )
}

@(test)
test_register_stdlib_modules_project_local_shadows_stdlib :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	project: build.Project_Discovery
	project.modules = make(map[base.Intern_ID]build.Module_Info, 8)
	project.module_names = make([dynamic]base.Intern_ID, 0, 8)

	result_name := base.intern(&ctx.interner, "Result")
	custom_source := "custom local Result"
	project.modules[result_name] = build.Module_Info{
		name = result_name,
		path = "src/Result.camp",
		content_hash = "custom_hash",
		source = custom_source,
		imports = make([dynamic]base.Deferred_Import, 0, 4),
		exports = make([dynamic]build.Export_Info, 0, 4),
	}
	append(&project.module_names, result_name)

	build.register_stdlib_modules(&project, &ctx.interner)
	defer build.project_discovery_destroy(&project)

	mi := project.modules[result_name]
	testing.expect(t, mi.source == custom_source, "Custom module source should not be overwritten by stdlib")
}

@(test)
test_register_stdlib_modules_idempotent :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	build.context_init(&ctx)
	defer build.context_destroy(&ctx)

	project: build.Project_Discovery
	project.modules = make(map[base.Intern_ID]build.Module_Info, 8)
	project.module_names = make([dynamic]base.Intern_ID, 0, 8)

	build.register_stdlib_modules(&project, &ctx.interner)
	first_count := len(project.modules)

	build.register_stdlib_modules(&project, &ctx.interner)
	defer build.project_discovery_destroy(&project)

	testing.expect(t, len(project.modules) == first_count,
		"Calling register_stdlib_modules twice should produce the same module count")
}
