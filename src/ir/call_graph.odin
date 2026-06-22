package ir

import "camp:base"

// Decl_Key is the identity of a declaration — module + name.
// Unlike Canonical_Name, it excludes is_local to avoid spurious
// mismatches between the name in IR_Call.callee and the name in IR_Decl_Fn.
Decl_Key :: struct {
	module: base.Intern_ID,
	name:   base.Intern_ID,
}

to_key :: proc(cn: base.Canonical_Name) -> Decl_Key {
	return Decl_Key{cn.module, cn.name}
}

NO_KEY :: Decl_Key{base.Intern_ID(-1), base.Intern_ID(-1)}

Call_Graph :: struct {
	edges:       map[Decl_Key][dynamic]Decl_Key,
	all_fns:     map[Decl_Key]bool,
	all_consts:  map[Decl_Key]bool,
	all_effects: map[Decl_Key]bool,
}

// build_call_graph constructs a directed call graph from an IR module.
// Edges are collected from:
//   - IR_Call.callee (direct calls)
//   - IR_Call trait dispatch fields (ord_compare_func, eq_func, debug_func, val_debug_func, hash_func)
//   - IR_Tail_Call.callee (tail calls)
//   - IR_Closure.fn_name (closure backing functions)
//   - IR_Perform.effect (effect invocations → effect defs)
//   - IR_Var references to top-level function names (closure fn_idx after closure conversion)
build_call_graph :: proc(mod: ^IR_Module) -> Call_Graph {
	graph: Call_Graph
	graph.edges = make(map[Decl_Key][dynamic]Decl_Key, len(mod.decls))
	graph.all_fns = make(map[Decl_Key]bool, len(mod.decls))
	graph.all_consts = make(map[Decl_Key]bool, len(mod.decls))
	graph.all_effects = make(map[Decl_Key]bool, len(mod.effect_defs))

	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			graph.all_fns[to_key(d.name)] = true
		case ^IR_Decl_Const:
			graph.all_consts[to_key(d.name)] = true
		case ^IR_Decl_Effect:
			graph.all_effects[to_key(d.name)] = true
		}
	}

	// Intern_ID → Decl_Key lookup for IR_Var → top-level decl matching.
	// Includes both functions and constants — constants are referenced
	// via IR_Var when used in other expressions.
	name_to_decl: map[base.Intern_ID]Decl_Key
	name_to_decl = make(map[base.Intern_ID]Decl_Key, len(graph.all_fns) + len(graph.all_consts))
	for key in graph.all_fns {
		name_to_decl[key.name] = key
	}
	for key in graph.all_consts {
		name_to_decl[key.name] = key
	}

	for decl in mod.decls {
		#partial switch d in decl {
		case ^IR_Decl_Fn:
			walk_expr_for_edges(d.body, to_key(d.name), &graph, &name_to_decl)
		case ^IR_Decl_Const:
			walk_expr_for_edges(d.value, to_key(d.name), &graph, &name_to_decl)
		case ^IR_Decl_Expect:
			walk_expr_for_edges(d.condition, NO_KEY, &graph, &name_to_decl)
		case ^IR_Decl_Effect:
		}
	}

	delete(name_to_decl)
	return graph
}

destroy_call_graph :: proc(graph: ^Call_Graph) {
	for _, v in graph.edges {
		delete(v)
	}
	delete(graph.edges)
	delete(graph.all_fns)
	delete(graph.all_consts)
	delete(graph.all_effects)
}

add_edge :: proc(graph: ^Call_Graph, source: Decl_Key, target: Decl_Key) {
	if target == NO_KEY do return
	tos := graph.edges[source]
	append(&tos, target)
	graph.edges[source] = tos
}

is_no_key :: proc(key: Decl_Key) -> bool {
	return key == NO_KEY || key.module == 0 && key.name == 0
}

// resolve_callee resolves a Canonical_Name (from IR_Call.callee etc.) to a Decl_Key.
// When module is NO_NAME (local calls before combine_module_irs sets the module),
// it falls back to the name_to_decl lookup by bare name.
resolve_callee :: proc(
	cn: base.Canonical_Name,
	name_to_decl: ^map[base.Intern_ID]Decl_Key,
) -> Decl_Key {
	if cn.module != base.NO_NAME {
		return to_key(cn)
	}
	// module == NO_NAME: resolve by bare name
	if key, ok := name_to_decl[cn.name]; ok {
		return key
	}
	return to_key(cn)
}

walk_expr_for_edges :: proc(
	expr: IR_Expr,
	source: Decl_Key,
	graph: ^Call_Graph,
	name_to_decl: ^map[base.Intern_ID]Decl_Key,
) {
	if expr == nil do return

	#partial switch e in expr {
	case ^IR_Call:
		add_edge(graph, source, resolve_callee(e.callee, name_to_decl))
		if !is_no_key(to_key(e.ord_compare_func)) do add_edge(graph, source, resolve_callee(e.ord_compare_func, name_to_decl))
		if !is_no_key(to_key(e.eq_func)) do add_edge(graph, source, resolve_callee(e.eq_func, name_to_decl))
		if !is_no_key(to_key(e.debug_func)) do add_edge(graph, source, resolve_callee(e.debug_func, name_to_decl))
		if !is_no_key(to_key(e.val_debug_func)) do add_edge(graph, source, resolve_callee(e.val_debug_func, name_to_decl))
		if !is_no_key(to_key(e.hash_func)) do add_edge(graph, source, resolve_callee(e.hash_func, name_to_decl))
		for arg in e.args {
			walk_expr_for_edges(arg, source, graph, name_to_decl)
		}

	case ^IR_Tail_Call:
		add_edge(graph, source, resolve_callee(e.callee, name_to_decl))
		for arg in e.args {
			walk_expr_for_edges(arg, source, graph, name_to_decl)
		}

	case ^IR_Closure:
		add_edge(graph, source, resolve_callee(e.fn_name, name_to_decl))
		walk_expr_for_edges(e.env, source, graph, name_to_decl)
		walk_expr_for_edges(e.body, source, graph, name_to_decl)

	case ^IR_Closure_Call:
		walk_expr_for_edges(e.callee, source, graph, name_to_decl)
		for arg in e.args {
			walk_expr_for_edges(arg, source, graph, name_to_decl)
		}

	case ^IR_Perform:
		add_edge(graph, source, resolve_callee(e.effect, name_to_decl))
		for arg in e.args {
			walk_expr_for_edges(arg, source, graph, name_to_decl)
		}

	case ^IR_Var:
		if target, ok := name_to_decl[e.name]; ok {
			add_edge(graph, source, target)
		}

	case ^IR_Let:
		walk_expr_for_edges(e.value, source, graph, name_to_decl)
		walk_expr_for_edges(e.body, source, graph, name_to_decl)

	case ^IR_If:
		walk_expr_for_edges(e.condition, source, graph, name_to_decl)
		walk_expr_for_edges(e.then_branch, source, graph, name_to_decl)
		walk_expr_for_edges(e.else_branch, source, graph, name_to_decl)

	case ^IR_Match:
		walk_expr_for_edges(e.scrutinee, source, graph, name_to_decl)
		for arm in e.arms {
			if arm.guard != nil {
				walk_expr_for_edges(arm.guard, source, graph, name_to_decl)
			}
			walk_expr_for_edges(arm.body, source, graph, name_to_decl)
		}

	case ^IR_Construct_Tag:
		for payload in e.payload {
			walk_expr_for_edges(payload, source, graph, name_to_decl)
		}

	case ^IR_Expr_Nominal_Construct:
		for payload in e.payload {
			walk_expr_for_edges(payload, source, graph, name_to_decl)
		}

	case ^IR_Construct_Record:
		for field in e.fields {
			walk_expr_for_edges(field.value, source, graph, name_to_decl)
		}
		walk_expr_for_edges(e.rest, source, graph, name_to_decl)

	case ^IR_Construct_Tuple:
		for el in e.elements {
			walk_expr_for_edges(el, source, graph, name_to_decl)
		}

	case ^IR_Field_Access:
		walk_expr_for_edges(e.record, source, graph, name_to_decl)

	case ^IR_Method_Call:
		walk_expr_for_edges(e.receiver, source, graph, name_to_decl)
		for arg in e.args {
			walk_expr_for_edges(arg, source, graph, name_to_decl)
		}

	case ^IR_Handle:
		for eff in e.effects {
			add_edge(graph, source, resolve_callee(eff, name_to_decl))
		}
		walk_expr_for_edges(e.body, source, graph, name_to_decl)
		for arm in e.arms {
			walk_expr_for_edges(arm.body, source, graph, name_to_decl)
		}

	case ^IR_Resume:
		walk_expr_for_edges(e.value, source, graph, name_to_decl)
		walk_expr_for_edges(e.ev, source, graph, name_to_decl)

	case ^IR_Block:
		for stmt in e.statements {
			walk_expr_for_edges(stmt, source, graph, name_to_decl)
		}

	case ^IR_BinOp:
		walk_expr_for_edges(e.left, source, graph, name_to_decl)
		walk_expr_for_edges(e.right, source, graph, name_to_decl)

	case ^IR_Crash:
		walk_expr_for_edges(e.message, source, graph, name_to_decl)

	case ^IR_I32_Load:
		walk_expr_for_edges(e.base, source, graph, name_to_decl)

	case ^IR_I32_Store:
		walk_expr_for_edges(e.base, source, graph, name_to_decl)
		walk_expr_for_edges(e.value, source, graph, name_to_decl)

	case ^IR_Atomic_Load:
		walk_expr_for_edges(e.base, source, graph, name_to_decl)

	case ^IR_Atomic_Store:
		walk_expr_for_edges(e.base, source, graph, name_to_decl)
		walk_expr_for_edges(e.value, source, graph, name_to_decl)

	case ^IR_Atomic_RMW:
		walk_expr_for_edges(e.base, source, graph, name_to_decl)
		walk_expr_for_edges(e.value, source, graph, name_to_decl)

	case ^IR_Wait:
		walk_expr_for_edges(e.base, source, graph, name_to_decl)
		walk_expr_for_edges(e.expected, source, graph, name_to_decl)
		walk_expr_for_edges(e.timeout, source, graph, name_to_decl)

	case ^IR_Notify:
		walk_expr_for_edges(e.base, source, graph, name_to_decl)
		walk_expr_for_edges(e.count, source, graph, name_to_decl)

	case ^IR_Return:
		walk_expr_for_edges(e.value, source, graph, name_to_decl)

	case ^IR_Assign:
		walk_expr_for_edges(e.value, source, graph, name_to_decl)

	case ^IR_Loop:
		walk_expr_for_edges(e.iterable, source, graph, name_to_decl)
		walk_expr_for_edges(e.body, source, graph, name_to_decl)

	// Leaves
	case ^IR_Literal_Int,
	     ^IR_Literal_Float,
	     ^IR_Literal_String,
	     ^IR_Literal_Bool,
	     ^IR_Dup,
	     ^IR_Drop,
	     ^IR_Atomic_Fence:
	}
}

