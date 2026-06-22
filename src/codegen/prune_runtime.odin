package codegen

// WASM-level runtime function pruning.
//
// After all code is emitted, scans function bodies for `call` opcodes
// targeting runtime function indices. Transitively closes the dependency
// graph, then replaces unused runtime function bodies with minimal
// `unreachable; end` stubs (2 bytes each).

// Max number of dependencies any runtime function can have.
MAX_RUNTIME_DEPS :: 6

// Dependency graph: for each Runtime_Func, stores up to MAX_RUNTIME_DEPS
// dependencies. Zero-valued entries (Runtime_Func(0) = Alloc) are valid
// deps, so we use a separate count array.
Runtime_Dep_Graph :: struct {
	deps:  [RUNTIME_FUNC_COUNT][MAX_RUNTIME_DEPS]Runtime_Func,
	count: [RUNTIME_FUNC_COUNT]int,
}

init_runtime_deps :: proc(g: ^Runtime_Dep_Graph) {
	add :: proc(g: ^Runtime_Dep_Graph, f: Runtime_Func, dep: Runtime_Func) {
		c := g.count[f]
		if c < MAX_RUNTIME_DEPS {
			g.deps[f][c] = dep
			g.count[f] = c + 1
		}
	}

	add(g, .Drop, .Dealloc)
	add(g, .Drop, .Report_Drop_Overflow)

	add(g, .List_Alloc, .Alloc)
	add(g, .List_Push, .List_Grow)
	add(g, .List_Grow, .Alloc)
	add(g, .List_Grow, .Dealloc)

	add(g, .Str_Concat, .Alloc)
	add(g, .Str_Slice, .Alloc)
	add(g, .I64_To_Str, .Alloc)
	add(g, .I32_To_Str, .Alloc)
	add(g, .F64_To_Str, .Alloc)
	add(g, .Bool_To_Str, .Alloc)

	add(g, .I64_Trampoline, .I64_Compare)
	add(g, .I64_Debug_Trampoline, .I64_To_Str)
	add(g, .Bool_Compare, .Alloc)

	// Container dispatch functions depend on trait callback functions.
	// The callbacks (I64_Compare, Bool_Compare, I64_Trampoline, etc.)
	// are stored in container headers and invoked via call_indirect.
	// We conservatively include all built-in type callbacks since we
	// can't determine the element type statically.

	// List dispatch
	add(g, .List_Compare, .Alloc)
	add(g, .List_Compare, .Drop)
	add(g, .List_Compare, .I64_Compare)
	add(g, .List_Compare, .I64_Trampoline)
	add(g, .List_Compare, .Bool_Compare)
	add(g, .List_Debug, .Str_Concat)
	add(g, .List_Debug, .I64_Debug_Trampoline)

	// Map dispatch — compare callbacks are invoked via call_indirect
	add(g, .Map_New, .Alloc)
	add(g, .Map_Insert, .Alloc)
	add(g, .Map_Insert, .I64_Compare)
	add(g, .Map_Insert, .I64_Trampoline)
	add(g, .Map_Insert, .Bool_Compare)
	add(g, .Map_Get, .Alloc)
	add(g, .Map_Get, .I64_Compare)
	add(g, .Map_Get, .I64_Trampoline)
	add(g, .Map_Get, .Bool_Compare)
	add(g, .Map_Contains, .I64_Compare)
	add(g, .Map_Contains, .I64_Trampoline)
	add(g, .Map_Contains, .Bool_Compare)
	add(g, .Map_Remove, .I64_Compare)
	add(g, .Map_Remove, .I64_Trampoline)
	add(g, .Map_Remove, .Bool_Compare)
	add(g, .Map_Singleton, .Alloc)
	add(g, .Map_Keys, .List_Alloc)
	add(g, .Map_Keys, .List_Push)
	add(g, .Map_Values, .List_Alloc)
	add(g, .Map_Values, .List_Push)
	add(g, .Map_Min, .Alloc)
	add(g, .Map_Max, .Alloc)
	add(g, .Set_Min, .Alloc)
	add(g, .Set_Max, .Alloc)
	add(g, .Map_Eq, .I64_Compare)
	add(g, .Map_Eq, .I64_Trampoline)
	add(g, .Map_Eq, .Bool_Compare)
	add(g, .Map_Debug, .Str_Concat)
	add(g, .Map_Debug, .I64_Debug_Trampoline)

	// Set dispatch
	add(g, .Set_Eq, .I64_Compare)
	add(g, .Set_Eq, .I64_Trampoline)
	add(g, .Set_Eq, .Bool_Compare)
	add(g, .Set_Debug, .Str_Concat)
	add(g, .Set_Debug, .I64_Debug_Trampoline)

	// Hash
	add(g, .Hash_Init, .Alloc)

	// Result dispatch
	add(g, .Result_Debug, .Str_Concat)
	add(g, .Result_Debug, .I64_Debug_Trampoline)
	add(g, .Result_Debug_I64, .Str_Concat)
	add(g, .Result_Debug_I64, .I64_To_Str)
	add(g, .Result_Debug_I64, .I64_Debug_Trampoline)
	add(g, .Result_Compare, .Alloc)
	add(g, .Result_Compare, .Drop)
	add(g, .Result_Compare, .I64_Compare)
	add(g, .Result_Compare, .I64_Trampoline)
	add(g, .Result_Compare, .Bool_Compare)
	add(g, .Result_Eq, .I64_Compare)
	add(g, .Result_Eq, .I64_Trampoline)
	add(g, .Result_Eq, .Bool_Compare)

	// Parallel
	add(g, .Parallel_Map, .Alloc)
	add(g, .Parallel_All, .Alloc)
	add(g, .Parallel_Filter, .Alloc)
}

// Runtime functions that must never be pruned. These are called via
// call_indirect (stored in container headers or closures) rather than
// direct `call` opcodes, so bytecode scanning alone cannot detect them.
//
// We conservatively keep: core RC/I/O, trait impl callbacks (compare,
// debug, trampoline), and container dispatch functions that internally
// use call_indirect to invoke callbacks. Container dispatch functions
// are called directly by emit_expr AND use call_indirect internally,
// so both the direct call and the indirect call paths must be valid.
ALWAYS_KEEP_RUNTIME :: []Runtime_Func {
	.Alloc,
	.Dup,
	.Drop,
	.Dealloc,
	.Exit,
	.Print_Str,
	.Print_Err,
	.Report_Drop_Overflow,
	.I64_Compare,
	.I64_Trampoline,
	.I64_Debug_Trampoline,
	.Bool_Compare,
	.List_Compare,
	.List_Hash,
	.List_Debug,
	.Map_Eq,
	.Set_Eq,
	.Map_Debug,
	.Set_Debug,
	.Result_Eq,
	.Result_Compare,
	.Result_Hash,
	.Result_Debug,
	.Result_Debug_I64,
}

// prune_unused_runtime_funcs scans all emitted WASM code bodies for
// direct `call` instructions targeting runtime function indices, then
// transitively closes the dependency graph. Unused runtime functions
// have their bodies replaced with 2-byte `unreachable; end` stubs.
prune_unused_runtime_funcs :: proc(mod: ^Wasm_Module, import_count: int) {
	used: [RUNTIME_FUNC_COUNT]bool

	// Mark always-keep functions
	for f in ALWAYS_KEEP_RUNTIME {
		used[f] = true
	}

	// Scan all code bodies for call opcodes targeting runtime functions.
	for code in mod.codes {
		targets := scan_calls_in_bytecode(code.body)
		for target in targets {
			idx := int(target)
			if idx >= import_count && idx < import_count + RUNTIME_FUNC_COUNT {
				used[idx - import_count] = true
			}
		}
		delete(targets)
	}

	// Transitively close dependencies.
	deps: Runtime_Dep_Graph
	init_runtime_deps(&deps)

	changed := true
	for changed {
		changed = false
		for f in 0 ..< RUNTIME_FUNC_COUNT {
			if !used[f] {
				continue
			}
			for di in 0 ..< deps.count[f] {
				dep := deps.deps[f][di]
				if !used[dep] {
					used[dep] = true
					changed = true
				}
			}
		}
	}

	// Replace unused runtime function bodies with stubs.
	for f in 0 ..< RUNTIME_FUNC_COUNT {
		if !used[f] && f < len(mod.codes) {
			delete(mod.codes[f].body)
			delete(mod.codes[f].locals)
			stub := make([]u8, 2)
			stub[0] = 0x00 // unreachable
			stub[1] = 0x0B // end
			mod.codes[f] = Wasm_Code {
				body = stub,
			}
		}
	}
}

