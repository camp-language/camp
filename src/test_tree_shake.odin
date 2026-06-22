package camp

import "camp:base"
import "camp:build"
import "camp:frontend"
import "camp:ir"
import "camp:semantics"
import "core:testing"

lower_to_post_pipeline :: proc(ctx: ^build.Compilation_Context, source: string) -> ir.IR_Module {
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File {
		path     = "<tree-shake-test>",
		contents = source,
		id       = 0,
	}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(canon, &store)
	semantics.check_effect_safety(tfile, &store)

	mod := ir.lower_tfile(tfile, &store)
	mod = ir.effect_lower(&mod, &ctx.interner, &ctx.collector, &store)
	mod = ir.closure_convert(&mod, &ctx.interner, &ctx.collector)
	mod = ir.cps_transform(&mod, &ctx.interner)
	ir.rc_insert(&mod, &ctx.interner)
	ir.reuse_analyze(&mod)
	return mod
}

teardown :: proc(ctx: ^build.Compilation_Context) {
	build.context_destroy(ctx)
}

find_key_by_name :: proc(
	graph: ^ir.Call_Graph,
	interner: ^base.Intern_Table,
	name_str: string,
) -> (
	ir.Decl_Key,
	bool,
) {
	name_id := base.intern(interner, name_str)
	for key in graph.all_fns {
		if key.name == name_id {
			return key, true
		}
	}
	for key in graph.all_consts {
		if key.name == name_id {
			return key, true
		}
	}
	return {}, false
}

@(test)
test_call_graph_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	mod := lower_to_post_pipeline(&ctx, "main! = || -> I64 { 42 }")
	defer teardown(&ctx)

	graph := ir.build_call_graph(&mod)
	defer ir.destroy_call_graph(&graph)

	main_key, found := find_key_by_name(&graph, &ctx.interner, "main!")
	testing.expect(t, found, "main! should be in graph")

	edges := graph.edges[main_key]
	testing.expect(t, len(edges) == 0, "pure main! should have no call edges")
}

@(test)
test_call_graph_with_call :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	mod := lower_to_post_pipeline(&ctx, "foo = || -> I64 { 1 }\nmain! = || -> I64 { foo() }")
	defer teardown(&ctx)

	graph := ir.build_call_graph(&mod)
	defer ir.destroy_call_graph(&graph)

	main_key, main_found := find_key_by_name(&graph, &ctx.interner, "main!")
	testing.expect(t, main_found, "main! should be in graph")

	_, foo_found := find_key_by_name(&graph, &ctx.interner, "foo")
	testing.expect(t, foo_found, "foo should be in graph")

	foo_id := base.intern(&ctx.interner, "foo")
	edges := graph.edges[main_key]
	has_foo_edge := false
	for edge in edges {
		if edge.name == foo_id {
			has_foo_edge = true
		}
	}
	testing.expect(t, has_foo_edge, "main! should call foo")
}

@(test)
test_reachable_simple :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	mod := lower_to_post_pipeline(&ctx, "foo = || -> I64 { 1 }\nmain! = || -> I64 { foo() }")
	defer teardown(&ctx)

	graph := ir.build_call_graph(&mod)
	defer ir.destroy_call_graph(&graph)

	main_key, main_found := find_key_by_name(&graph, &ctx.interner, "main!")
	testing.expect(t, main_found)

	foo_id := base.intern(&ctx.interner, "foo")
	main_id := base.intern(&ctx.interner, "main!")

	roots := []ir.Decl_Key{main_key}
	reachable := ir.mark_reachable(&graph, roots)
	defer delete(reachable)

	main_reachable := false
	foo_reachable := false
	for key in reachable {
		if key.name == main_id do main_reachable = true
		if key.name == foo_id do foo_reachable = true
	}
	testing.expect(t, main_reachable, "main! should be reachable")
	testing.expect(t, foo_reachable, "foo should be reachable from main!")
}

@(test)
test_prune_removes_unreachable :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	mod := lower_to_post_pipeline(
		&ctx,
		"foo = || -> I64 { 1 }\nbar = || -> I64 { 2 }\nmain! = || -> I64 { foo() }",
	)
	defer teardown(&ctx)

	original_count := len(mod.decls)

	graph := ir.build_call_graph(&mod)
	defer ir.destroy_call_graph(&graph)

	main_key, main_found := find_key_by_name(&graph, &ctx.interner, "main!")
	testing.expect(t, main_found)

	foo_id := base.intern(&ctx.interner, "foo")
	bar_id := base.intern(&ctx.interner, "bar")
	main_id := base.intern(&ctx.interner, "main!")

	roots := []ir.Decl_Key{main_key}
	reachable := ir.mark_reachable(&graph, roots)
	defer delete(reachable)

	ir.prune_module(&mod, &reachable)

	bar_found := false
	foo_found := false
	main_found = false
	for decl in mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if d.name.name == bar_id do bar_found = true
			if d.name.name == foo_id do foo_found = true
			if d.name.name == main_id do main_found = true
		}
	}

	testing.expect(t, main_found, "main! should survive pruning")
	testing.expect(t, foo_found, "foo (reachable) should survive pruning")
	testing.expect(t, !bar_found, "bar (unreachable) should be removed")
	testing.expect(t, len(mod.decls) < original_count, "pruning should reduce decl count")
}

@(test)
test_no_root_skips_shaking :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	mod := lower_to_post_pipeline(&ctx, "foo = || -> I64 { 1 }")
	defer teardown(&ctx)

	original_count := len(mod.decls)

	ir.tree_shake_module(&mod, &ctx.interner)

	testing.expect(t, len(mod.decls) == original_count, "no main! should skip tree shaking")
}

@(test)
test_self_recursive_fn :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	mod := lower_to_post_pipeline(
		&ctx,
		"countdown = |n: I64| -> I64 { if n == 0 { 0 } else { countdown(n - 1) } }\nmain! = || -> I64 { countdown(10) }",
	)
	defer teardown(&ctx)

	graph := ir.build_call_graph(&mod)
	defer ir.destroy_call_graph(&graph)

	main_key, main_found := find_key_by_name(&graph, &ctx.interner, "main!")
	testing.expect(t, main_found)

	countdown_id := base.intern(&ctx.interner, "countdown")

	roots := []ir.Decl_Key{main_key}
	reachable := ir.mark_reachable(&graph, roots)
	defer delete(reachable)

	countdown_found := false
	for key in reachable {
		if key.name == countdown_id do countdown_found = true
	}
	testing.expect(t, countdown_found, "self-recursive fn should be reachable")
}

@(test)
test_tree_shake_module :: proc(t: ^testing.T) {
	ctx: build.Compilation_Context
	mod := lower_to_post_pipeline(&ctx, "unused = || -> I64 { 99 }\nmain! = || -> I64 { 42 }")
	defer teardown(&ctx)

	original_count := len(mod.decls)
	ir.tree_shake_module(&mod, &ctx.interner)

	testing.expect(
		t,
		len(mod.decls) < original_count,
		"tree_shake_module should remove unused decls",
	)

	unused_id := base.intern(&ctx.interner, "unused")
	for decl in mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			testing.expect(
				t,
				d.name.name != unused_id,
				"unused fn should be removed by tree_shake_module",
			)
		}
	}
}

