package base

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

hash_string :: proc(s: string) -> int {
	h: int = 5381
	for i := 0; i < len(s); i += 1 {
		h = ((h << 5) + h) + int(s[i])
	}
	return h
}

mangle_name :: proc(module: Intern_ID, name: Intern_ID, interner: ^Intern_Table) -> string {
	module_str := intern_get(interner, module)
	name_str := intern_get(interner, name)
	builder: strings.Builder
	strings.builder_init_len_cap(&builder, 0, len(module_str) + len(name_str) + 4)
	for i := 0; i < len(module_str); i += 1 {
		if module_str[i] == '.' {
			strings.write_byte(&builder, '_')
		} else {
			strings.write_byte(&builder, module_str[i])
		}
	}
	strings.write_string(&builder, "__")
	strings.write_string(&builder, name_str)
	result := strings.to_string(builder)
	strings.builder_destroy(&builder)
	return result
}
