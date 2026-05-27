package camp_toml

import "core:fmt"
import "core:mem"
import "core:strings"

Package_Meta :: struct {
	name:        string,
	version:     string,
	description: string,
	licenses:    [dynamic]string,
}

Dep_Entry :: struct {
	alias: string,
	uri:   string,
}

Camp_Toml :: struct {
	pkg:              Package_Meta,
	dependencies:     [dynamic]Dep_Entry,
	dev_dependencies: [dynamic]Dep_Entry,
}

Parse_Error :: struct {
	line: int,
	msg:  string,
}

_Parsed :: struct {
	pkg:              Package_Meta,
	dependencies:     [dynamic]Dep_Entry,
	dev_dependencies: [dynamic]Dep_Entry,
	errors:           [dynamic]Parse_Error,
}

parse :: proc(input: string, allocator: mem.Allocator) -> Camp_Toml {
	pr := _parse(input, allocator)

	for err in pr.errors {
		fmt.eprintln("camp.toml:", err.line, ":", err.msg)
	}

	return Camp_Toml{
		pkg = pr.pkg,
		dependencies = pr.dependencies,
		dev_dependencies = pr.dev_dependencies,
	}
}

_parse :: proc(input: string, allocator: mem.Allocator) -> _Parsed {
	result: _Parsed
	result.dependencies = make([dynamic]Dep_Entry, 0, 8, allocator)
	result.dev_dependencies = make([dynamic]Dep_Entry, 0, 4, allocator)
	result.errors = make([dynamic]Parse_Error, 0, 4, allocator)

	current_section: enum {None, Package, Dependencies, Dev_Dependencies} = .None
	lines := strings.split_lines(input, allocator)

	for line_str, line_idx in lines {
		trimmed := strings.trim_space(line_str)
		if len(trimmed) == 0 || trimmed[0] == '#' {continue}

		// Section header: [section_name]
		if trimmed[0] == '[' && strings.contains(trimmed, "]") {
			closing := strings.index(trimmed, "]")
			if closing == -1 {continue}
			section_name := strings.trim_space(trimmed[1:closing])
			switch section_name {
			case "package":
				current_section = .Package
			case "dependencies":
				current_section = .Dependencies
			case "dev-dependencies":
				current_section = .Dev_Dependencies
			case:
				append(&result.errors, Parse_Error{line = line_idx + 1, msg = fmt.tprintf("unknown section [{}]", section_name)})
				current_section = .None
			}
			continue
		}

		// Package field
		if current_section == .Package && strings.contains(trimmed, "=") {
			eq := strings.index(trimmed, "=")
			if eq == -1 {continue}
			key := strings.trim_space(trimmed[:eq])
			val_str := strings.trim_space(trimmed[eq + 1:])

			switch key {
			case "name":
				result.pkg.name = _unquote(val_str, allocator)
			case "version":
				result.pkg.version = _unquote(val_str, allocator)
			case "description":
				result.pkg.description = _unquote(val_str, allocator)
			case "licenses":
				result.pkg.licenses = _parse_string_array(val_str, allocator)
			}
			continue
		}

		// Dependency entry
		if (current_section == .Dependencies || current_section == .Dev_Dependencies) && strings.contains(trimmed, "=") {
			eq := strings.index(trimmed, "=")
			if eq == -1 {continue}
			alias := strings.trim_space(trimmed[:eq])
			uri := strings.trim_space(trimmed[eq + 1:])
			uri = _unquote(uri, allocator)

			entry := Dep_Entry{alias = alias, uri = uri}
			if current_section == .Dependencies {
				append(&result.dependencies, entry)
			} else {
				append(&result.dev_dependencies, entry)
			}
			continue
		}
	}

	return result
}

_unquote :: proc(s: string, allocator: mem.Allocator) -> string {
	t := strings.trim_space(s)
	if len(t) >= 2 && t[0] == '"' && t[len(t) - 1] == '"' {
		return strings.clone(t[1:len(t) - 1], allocator)
	}
	return t
}

_parse_string_array :: proc(s: string, allocator: mem.Allocator) -> [dynamic]string {
	arr := make([dynamic]string, 0, 4, allocator)
	t := strings.trim_space(s)
	if len(t) >= 2 && t[0] == '[' && t[len(t) - 1] == ']' {
		inner := strings.trim_space(t[1:len(t) - 1])
		if len(inner) == 0 {return arr}
		parts := strings.split(inner, ",", allocator)
		for part in parts {
			unquoted := _unquote(strings.trim_space(part), allocator)
			if len(unquoted) > 0 {append(&arr, unquoted)}
		}
	}
	return arr
}

Validation_Error :: struct {
	msg: string,
}

validate :: proc(t: Camp_Toml, allocator: mem.Allocator) -> [dynamic]Validation_Error {
	errors := make([dynamic]Validation_Error, 0, 4, allocator)

	if len(t.pkg.name) == 0 {
		append(&errors, Validation_Error{msg = "`name` is required in [package]"})
	}
	if len(t.pkg.version) == 0 {
		append(&errors, Validation_Error{msg = "`version` is required in [package]"})
	}
	if t.pkg.licenses != nil && len(t.pkg.licenses) == 0 {
		append(&errors, Validation_Error{msg = "`licenses` must be non-empty when present"})
	}

	for dep in t.dependencies {
		if !_is_snake_case(dep.alias) {
			append(&errors, Validation_Error{
				msg = fmt.tprintf("dependency alias '{}' must be snake_case", dep.alias),
			})
		}
		if len(dep.uri) == 0 {
			append(&errors, Validation_Error{
				msg = fmt.tprintf("dependency '{}' has empty URI", dep.alias),
			})
		}
	}
	for dep in t.dev_dependencies {
		if !_is_snake_case(dep.alias) {
			append(&errors, Validation_Error{
				msg = fmt.tprintf("dev-dependency alias '{}' must be snake_case", dep.alias),
			})
		}
		if len(dep.uri) == 0 {
			append(&errors, Validation_Error{
				msg = fmt.tprintf("dev-dependency '{}' has empty URI", dep.alias),
			})
		}
	}

	return errors
}

_is_snake_case :: proc(s: string) -> bool {
	if len(s) == 0 {return false}
	for r in s {
		if !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_') {return false}
	}
	if s[0] >= '0' && s[0] <= '9' {return false}
	if strings.contains(s, "__") {return false}
	if s[0] == '_' || s[len(s) - 1] == '_' {return false}
	return true
}
