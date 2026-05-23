package camp

import "core:fmt"

Fresh_State :: struct {
	counter:  int,
	interner: ^Intern_Table,
}

fresh_id :: proc(state: ^Fresh_State, prefix: string) -> Intern_ID {
	name := fmt.tprintf("{}_{}", prefix, state.counter)
	state.counter += 1
	return intern(state.interner, name)
}
