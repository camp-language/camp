package camp

import "core:mem"
import "core:mem/virtual"

Compilation_Context :: struct {
	arena:          virtual.Arena,
	allocator:      mem.Allocator,
	interner:       Intern_Table,
	collector:      Diagnostic_Collector,
	project:        Project_Discovery,
	export_tables:  map[Intern_ID]Export_Table,
	module_stores:  map[Intern_ID]Type_Store,
}

context_init :: proc(ctx: ^Compilation_Context) -> mem.Allocator {
	err := virtual.arena_init_growing(&ctx.arena)
	if err != nil {
		return mem.Allocator{}
	}
	ctx.allocator = virtual.arena_allocator(&ctx.arena)
	intern_init(&ctx.interner)
	diag_collector_init(&ctx.collector)
	ctx.export_tables = make(map[Intern_ID]Export_Table, 16)
	ctx.module_stores = make(map[Intern_ID]Type_Store, 16)
	return ctx.allocator
}

context_destroy :: proc(ctx: ^Compilation_Context) {
	for _, &et in ctx.export_tables {
		export_table_destroy(&et)
	}
	delete(ctx.export_tables)

	for _, &store in ctx.module_stores {
		type_store_destroy(&store)
	}
	delete(ctx.module_stores)

	project_discovery_destroy(&ctx.project)
	diag_collector_destroy(&ctx.collector)
	intern_destroy(&ctx.interner)
	virtual.arena_destroy(&ctx.arena)
}
