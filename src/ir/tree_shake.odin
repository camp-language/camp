package ir

import "camp:base"

// find_roots scans the IR module for entry point functions (main, main!)
// and returns them as the root set for reachability analysis.
find_roots :: proc(mod: ^IR_Module, interner: ^base.Intern_Table) -> []Decl_Key {
	roots: [dynamic]Decl_Key

	main_id := base.intern(interner, "main")
	main_bang_id := base.intern(interner, "main!")

	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			if d.name.name == main_id || d.name.name == main_bang_id {
				append(&roots, to_key(d.name))
			}
		}
	}

	return roots[:]
}

// find_roots_with_tests extends find_roots with test function detection.
find_roots_with_tests :: proc(
	mod: ^IR_Module,
	interner: ^base.Intern_Table,
	test_names: map[Decl_Key]bool,
) -> []Decl_Key {
	roots: [dynamic]Decl_Key

	main_id := base.intern(interner, "main")
	main_bang_id := base.intern(interner, "main!")

	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			key := to_key(d.name)
			if d.name.name == main_id || d.name.name == main_bang_id {
				append(&roots, key)
			} else if test_names[key] {
				append(&roots, key)
			}
		}
	}

	return roots[:]
}

// mark_reachable performs BFS from the root set over the call graph,
// returning the set of all reachable declarations.
mark_reachable :: proc(graph: ^Call_Graph, roots: []Decl_Key) -> map[Decl_Key]bool {
	reachable := make(
		map[Decl_Key]bool,
		len(graph.all_fns) + len(graph.all_consts) + len(graph.all_effects),
	)

	queue: [dynamic]Decl_Key
	defer delete(queue)

	for root in roots {
		if !reachable[root] {
			reachable[root] = true
			append(&queue, root)
		}
	}

	head := 0
	for head < len(queue) {
		current := queue[head]
		head += 1

		if neighbors, ok := graph.edges[current]; ok {
			for neighbor in neighbors {
				if !reachable[neighbor] {
					reachable[neighbor] = true
					append(&queue, neighbor)
				}
			}
		}
	}

	return reachable
}

// tree_shake_module removes unreachable declarations from the IR module.
// It operates in-place, filtering mod.decls and mod.effect_defs to
// only include entries present in the reachable set.
tree_shake_module :: proc(mod: ^IR_Module, interner: ^base.Intern_Table) {
	graph := build_call_graph(mod)
	defer destroy_call_graph(&graph)

	roots := find_roots(mod, interner)
	if len(roots) == 0 {
		return
	}
	defer delete(roots)

	reachable := mark_reachable(&graph, roots)
	defer delete(reachable)

	prune_module(mod, &reachable)
}

// tree_shake_module_with_tests is like tree_shake_module but also
// considers test functions as roots.
tree_shake_module_with_tests :: proc(
	mod: ^IR_Module,
	interner: ^base.Intern_Table,
	test_names: map[Decl_Key]bool,
) {
	graph := build_call_graph(mod)
	defer destroy_call_graph(&graph)

	roots := find_roots_with_tests(mod, interner, test_names)
	if len(roots) == 0 {
		return
	}
	defer delete(roots)

	reachable := mark_reachable(&graph, roots)
	defer delete(reachable)

	prune_module(mod, &reachable)
}

// prune_module filters the module's declarations and effect definitions
// to only those present in the reachable set.
prune_module :: proc(mod: ^IR_Module, reachable: ^map[Decl_Key]bool) {
	new_decls := make([dynamic]IR_Decl, 0, len(mod.decls))
	for decl in mod.decls {
		keep := false
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			keep = reachable[to_key(d.name)]
		case ^IR_Decl_Const:
			keep = reachable[to_key(d.name)]
		case ^IR_Decl_Effect:
			keep = reachable[to_key(d.name)]
		case ^IR_Decl_Expect:
			keep = true
		}
		if keep {
			append(&new_decls, decl)
		}
		// Unreachable declarations are dropped from the slice.
		// Memory is managed by the context allocator — no individual free needed.
	}

	delete(mod.decls)
	mod.decls = new_decls

	new_effects := make([dynamic]IR_Effect_Def, 0, len(mod.effect_defs))
	for eff in mod.effect_defs {
		if reachable[to_key(eff.name)] {
			append(&new_effects, eff)
		}
		// Unreachable effect defs are dropped — memory managed by context allocator.
	}
	delete(mod.effect_defs)
	mod.effect_defs = new_effects
}

