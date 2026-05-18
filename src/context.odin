package camp

import "core:mem"
import "core:mem/virtual"

Compilation_Context :: struct {
	arena:     virtual.Arena,
	allocator: mem.Allocator,
	interner:   Intern_Table,
	collector:  Error_Collector,
}

context_init :: proc(ctx: ^Compilation_Context) -> mem.Allocator {
	err := virtual.arena_init_growing(&ctx.arena)
	if err != nil {
		return mem.Allocator{}
	}
	ctx.allocator = virtual.arena_allocator(&ctx.arena)
	intern_init(&ctx.interner)
	collector_init(&ctx.collector)
	return ctx.allocator
}

context_destroy :: proc(ctx: ^Compilation_Context) {
	collector_destroy(&ctx.collector)
	intern_destroy(&ctx.interner)
	virtual.arena_destroy(&ctx.arena)
}
