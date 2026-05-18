package camp

import "core:strings"

Intern_ID :: distinct int

Intern_Table :: struct {
	strings: map[string]Intern_ID,
	ids:     [dynamic]string,
	next_id: Intern_ID,
}

intern_init :: proc(table: ^Intern_Table) {
	table.strings = make(map[string]Intern_ID, 256)
	table.ids = make([dynamic]string, 0, 256)
	table.next_id = 0
}

intern_destroy :: proc(table: ^Intern_Table) {
	delete(table.strings)
	delete(table.ids)
}

intern :: proc(table: ^Intern_Table, s: string) -> Intern_ID {
	if existing, ok := table.strings[s]; ok {
		return existing
	}
	id := table.next_id
	table.next_id += 1
	table.strings[s] = id
	append(&table.ids, s)
	return id
}

intern_get :: proc(table: ^Intern_Table, id: Intern_ID) -> string {
	return table.ids[int(id)]
}
