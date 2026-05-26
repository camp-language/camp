package build

import "camp:base"
import "camp:diagnostics"
import "core:fmt"
import "core:strings"

Module_Graph :: struct {
	edges:     map[base.Intern_ID][dynamic]base.Intern_ID,
	all_nodes: [dynamic]base.Intern_ID,
}

module_graph_init :: proc(graph: ^Module_Graph) {
	graph.edges = make(map[base.Intern_ID][dynamic]base.Intern_ID, 32)
	graph.all_nodes = make([dynamic]base.Intern_ID, 0, 32)
}

module_graph_destroy :: proc(graph: ^Module_Graph) {
	for _, edges in graph.edges {
		delete(edges)
	}
	delete(graph.edges)
	delete(graph.all_nodes)
}

module_graph_add_edge :: proc(graph: ^Module_Graph, from: base.Intern_ID, to: base.Intern_ID) {
	if _, ok := graph.edges[from]; !ok {
		graph.edges[from] = make([dynamic]base.Intern_ID, 0, 8)
	}
	append(&graph.edges[from], to)
}

module_graph_add_node :: proc(graph: ^Module_Graph, node: base.Intern_ID) {
	if _, ok := graph.edges[node]; !ok {
		graph.edges[node] = make([dynamic]base.Intern_ID, 0, 8)
	}
	append(&graph.all_nodes, node)
}

build_module_graph :: proc(
	project: ^Project_Discovery,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
) -> Module_Graph {
	graph: Module_Graph
	module_graph_init(&graph)

	for _, mi in project.modules {
		module_graph_add_node(&graph, mi.name)
	}

	for _, mi in project.modules {
		for imp in mi.imports {
			mod_name := imp.module
			if _, ok := project.modules[mod_name]; !ok {
				mod_str := base.intern_get(interner, mod_name)
				diagnostics.collector_add_diag(
					collector,
					diagnostics.diag_module_not_found(mod_str, imp.span),
				)
				continue
			}
			module_graph_add_edge(&graph, mi.name, mod_name)
		}
	}

	return graph
}

topological_sort :: proc(
	graph: ^Module_Graph,
	interner: ^base.Intern_Table,
	collector: ^diagnostics.Diagnostic_Collector,
) -> (
	[]base.Intern_ID,
	bool,
) {
	in_degree: map[base.Intern_ID]int
	in_degree = make(map[base.Intern_ID]int, len(graph.all_nodes))
	defer delete(in_degree)

	for node in graph.all_nodes {
		in_degree[node] = 0
	}

	for _, edges in graph.edges {
		for to in edges {
			if _, ok := in_degree[to]; ok {
				in_degree[to] += 1
			}
		}
	}

	queue: [dynamic]base.Intern_ID
	queue = make([dynamic]base.Intern_ID, 0, len(graph.all_nodes))

	for node in graph.all_nodes {
		if in_degree[node] == 0 {
			append(&queue, node)
		}
	}

	result: [dynamic]base.Intern_ID
	result = make([dynamic]base.Intern_ID, 0, len(graph.all_nodes))

	queue_idx := 0
	for queue_idx < len(queue) {
		node := queue[queue_idx]
		queue_idx += 1
		append(&result, node)

		if edges, ok := graph.edges[node]; ok {
			for to in edges {
				in_degree[to] -= 1
				if in_degree[to] == 0 {
					append(&queue, to)
				}
			}
		}
	}

	defer delete(queue)

	if len(result) == len(graph.all_nodes) {
		return result[:], true
	}

	cycle := find_cycle(graph, interner)
	diagnostics.collector_add_diag(
		collector,
		diagnostics.diag_cyclic_dependency(cycle, base.Source_Span_ZERO),
	)

	delete(result)
	return nil, false
}

DFS_Color :: enum int {
	White = 0,
	Gray  = 1,
	Black = 2,
}

find_cycle :: proc(graph: ^Module_Graph, interner: ^base.Intern_Table) -> string {
	white: map[base.Intern_ID]DFS_Color
	white = make(map[base.Intern_ID]DFS_Color, len(graph.all_nodes))
	defer delete(white)

	parent: map[base.Intern_ID]base.Intern_ID
	parent = make(map[base.Intern_ID]base.Intern_ID, len(graph.all_nodes))
	defer delete(parent)

	path: [dynamic]base.Intern_ID
	path = make([dynamic]base.Intern_ID, 0, 16)
	defer delete(path)

	for start in graph.all_nodes {
		if white[start] != .White do continue

		stack: [dynamic]base.Intern_ID
		stack = make([dynamic]base.Intern_ID, 0, 16)
		append(&stack, start)
		defer delete(stack)

		for len(stack) > 0 {
			node := pop(&stack)

			if white[node] == .White {
				white[node] = .Gray
				append(&stack, node)

				if edges, ok := graph.edges[node]; ok {
					for to in edges {
						if white[to] == .White {
							parent[to] = node
							append(&stack, to)
						} else if white[to] == .Gray {
							cycle_start := to
							clear(&path)
							cur: base.Intern_ID = node
							append(&path, cycle_start)
							for cur != cycle_start {
								append(&path, cur)
								if p, pok := parent[cur]; pok {
									cur = p
								} else {
									break
								}
							}
							append(&path, cycle_start)

							builder: strings.Builder
							strings.builder_init_len_cap(&builder, 0, 256)
							for i := len(path) - 1; i >= 0; i -= 1 {
								if i < len(path) - 1 {
									strings.write_string(&builder, " → ")
								}
								strings.write_string(&builder, base.intern_get(interner, path[i]))
							}
							return strings.to_string(builder)
						}
					}
				}
			} else if white[node] == .Gray {
				white[node] = .Black
			}
		}
	}

	return "cycle"
}

