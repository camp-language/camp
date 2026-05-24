package build

import "camp:base"
import "camp:diagnostics"
import "camp:semantics"
import "core:mem"
import "core:mem/virtual"

Compilation_Context :: struct {
	arena:          virtual.Arena,
	allocator:      mem.Allocator,
	interner:       base.Intern_Table,
	collector:      diagnostics.Diagnostic_Collector,
	project:        Project_Discovery,
	export_tables:  map[base.Intern_ID]Export_Table,
	module_stores:  map[base.Intern_ID]semantics.Type_Store,
	type_store:     ^semantics.Type_Store,
	thread_count:   int,
}

context_init :: proc(ctx: ^Compilation_Context) -> mem.Allocator {
	err := virtual.arena_init_growing(&ctx.arena)
	if err != nil {
		return mem.Allocator{}
	}
	ctx.allocator = virtual.arena_allocator(&ctx.arena)
	base.intern_init(&ctx.interner)
	diagnostics.diag_collector_init(&ctx.collector)
	ctx.export_tables = make(map[base.Intern_ID]Export_Table, 16)
	ctx.module_stores = make(map[base.Intern_ID]semantics.Type_Store, 16)
	ctx.type_store = nil
	ctx.thread_count = 1
	return ctx.allocator
}

context_destroy :: proc(ctx: ^Compilation_Context) {
	for _, &et in ctx.export_tables {
		export_table_destroy(&et)
	}
	delete(ctx.export_tables)

	for _, &store in ctx.module_stores {
		semantics.type_store_destroy(&store)
	}
	delete(ctx.module_stores)

	project_discovery_destroy(&ctx.project)
	diagnostics.diag_collector_destroy(&ctx.collector)
	base.intern_destroy(&ctx.interner)
	virtual.arena_destroy(&ctx.arena)
}
