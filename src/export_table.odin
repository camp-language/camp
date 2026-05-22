package camp

Export_Kind :: enum {
	Const,
	Effect,
	Trait,
	Alias,
	Newtype,
}

Export_Info :: struct {
	name:         Intern_ID,
	kind:         Export_Kind,
	is_pub:       bool,
	pub_variants: bool,
	type_var:     Type_Var_ID,
}

Export_Table :: struct {
	exports: map[Intern_ID]Export_Info,
}

export_table_init :: proc(table: ^Export_Table) {
	table.exports = make(map[Intern_ID]Export_Info, 32)
}

export_table_destroy :: proc(table: ^Export_Table) {
	delete(table.exports)
}

collect_exports :: proc(cfile: CFile, store: ^Type_Store) -> Export_Table {
	table: Export_Table
	export_table_init(&table)

	for decl in cfile.decls {
		#partial switch d in decl {
		case ^CDecl_Const:
			if d.is_pub {
				ei := Export_Info{
					name = d.name.name,
					kind = .Const,
					is_pub = true,
					type_var = Type_Var_ID(-1),
				}
				if existing, ok := store.bindings[d.name.name]; ok {
					ei.type_var = existing
				}
				table.exports[d.name.name] = ei
			}
		case ^CDecl_Effect:
			if d.is_pub {
				table.exports[d.name.name] = Export_Info{
					name = d.name.name,
					kind = .Effect,
					is_pub = true,
					type_var = Type_Var_ID(-1),
				}
			}
		case ^CDecl_Trait:
			if d.is_pub {
				table.exports[d.name.name] = Export_Info{
					name = d.name.name,
					kind = .Trait,
					is_pub = true,
					type_var = Type_Var_ID(-1),
				}
			}
		case ^CDecl_Alias:
			if d.is_pub {
				table.exports[d.name.name] = Export_Info{
					name = d.name.name,
					kind = .Alias,
					is_pub = true,
					type_var = Type_Var_ID(-1),
				}
			}
		case ^CDecl_Newtype:
			if d.is_pub {
				table.exports[d.name.name] = Export_Info{
					name = d.name.name,
					kind = .Newtype,
					is_pub = true,
					pub_variants = d.pub_variants,
					type_var = Type_Var_ID(-1),
				}
			}
		case:
		}
	}

	return table
}

export_lookup :: proc(table: ^Export_Table, name: Intern_ID) -> (Export_Info, bool) {
	if existing, ok := table.exports[name]; ok {
		return existing, true
	}
	return Export_Info{}, false
}

export_is_pub :: proc(table: ^Export_Table, name: Intern_ID) -> bool {
	ei, ok := export_lookup(table, name)
	if !ok {
		return false
	}
	return ei.is_pub
}
