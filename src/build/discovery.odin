package build

import "camp:base"
import "camp:semantics"
import "camp:diagnostics"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

Module_Info :: struct {
	name:         base.Intern_ID,
	path:         string,
	content_hash: string,
	source:       string,
	cfile:        ^semantics.CFile,
	imports:      [dynamic]base.Deferred_Import,
	exports:      [dynamic]Export_Info,
}

Project_Discovery :: struct {
	root_dir:     string,
	src_dir:      string,
	modules:      map[base.Intern_ID]Module_Info,
	module_names: [dynamic]base.Intern_ID,
	entry_point:  base.Intern_ID,
}

discover_project :: proc(cwd: string, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector, allocator: mem.Allocator) -> Project_Discovery {
	project: Project_Discovery
	project.modules = make(map[base.Intern_ID]Module_Info, 32)
	project.module_names = make([dynamic]base.Intern_ID, 0, 32)

	root := find_project_root(cwd, allocator)
	if root == "" {
		diagnostics.collector_add_diag(collector, diagnostics.diag_project_no_source())
		return project
	}

	project.root_dir = root
	project.src_dir, _ = filepath.join({root, "src"}, allocator)

	walk_src_dir(project.src_dir, interner, collector, allocator, &project.modules, &project.module_names)

	entry_name := base.intern(interner, "Main")
	if _, ok := project.modules[entry_name]; ok {
		project.entry_point = entry_name
	} else {
		project.entry_point = base.NO_NAME
	}

	return project
}

find_project_root :: proc(start_dir: string, allocator: mem.Allocator) -> string {
	dir := start_dir
	for {
		src_path, _ := filepath.join({dir, "src"}, allocator)
		ok := dir_has_camp_files(src_path, allocator)
		delete(src_path, allocator)
		if ok {
			return dir
		}
		parent := filepath.dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

dir_has_camp_files :: proc(dir: string, allocator: mem.Allocator) -> bool {
	infos, err := os.read_all_directory_by_path(dir, allocator)
	if err != nil {
		return false
	}
	defer os.file_info_slice_delete(infos, allocator)

	for fi in infos {
		if fi.type == .Regular && strings.has_suffix(fi.name, ".camp") {
			return true
		}
	}

	subdirs: [dynamic]string
	subdirs.allocator = allocator
	defer delete(subdirs)

	for fi in infos {
		if fi.type == .Directory && fi.name != "." && fi.name != ".." {
			sub_path, _ := filepath.join({dir, fi.name}, allocator)
			append(&subdirs, sub_path)
		}
	}

	for sub in subdirs {
		if dir_has_camp_files(sub, allocator) {
			return true
		}
	}

	return false
}

walk_src_dir :: proc(src_dir: string, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector, allocator: mem.Allocator, modules: ^map[base.Intern_ID]Module_Info, module_names: ^[dynamic]base.Intern_ID) {
	walk_dir_recursive(src_dir, src_dir, interner, collector, allocator, modules, module_names)
}

walk_dir_recursive :: proc(current_dir: string, src_dir: string, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector, allocator: mem.Allocator, modules: ^map[base.Intern_ID]Module_Info, module_names: ^[dynamic]base.Intern_ID) {
	infos, err := os.read_all_directory_by_path(current_dir, allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(infos, allocator)

	for fi in infos {
		if fi.type == .Regular && strings.has_suffix(fi.name, ".camp") {
			file_path, _ := filepath.join({current_dir, fi.name}, allocator)

			module_name := path_to_module_name(file_path, src_dir, interner)

			data, read_err := os.read_entire_file(file_path, allocator)
			if read_err != nil {
				diagnostics.collector_add_diag(collector, diagnostics.diag_file_not_found(file_path, fmt.tprintf("{}", read_err)))
				continue
			}

			mi := Module_Info{
				name = module_name,
				path = file_path,
				content_hash = simple_hash(string(data)),
				source = string(data),
				imports = make([dynamic]base.Deferred_Import, 0, 8),
				exports = make([dynamic]Export_Info, 0, 16),
			}

			modules^[module_name] = mi
			append(module_names, module_name)
		}

		if fi.type == .Directory && fi.name != "." && fi.name != ".." {
			sub_path, _ := filepath.join({current_dir, fi.name}, allocator)
			walk_dir_recursive(sub_path, src_dir, interner, collector, allocator, modules, module_names)
			delete(sub_path, allocator)
		}
	}
}

path_to_module_name :: proc(file_path: string, src_dir: string, interner: ^base.Intern_Table) -> base.Intern_ID {
	prefix := src_dir
	owns_prefix := false
	if !strings.has_suffix(prefix, "/") {
		prefix = fmt.tprintf("{}/", prefix)
		owns_prefix = true
	}
	defer if owns_prefix do delete(prefix)

	rel := file_path
	if strings.has_prefix(file_path, prefix) {
		rel = file_path[len(prefix):]
	}

	rel = strings.trim_suffix(rel, ".camp")

	builder: strings.Builder
	strings.builder_init_len_cap(&builder, 0, len(rel))
	for i := 0; i < len(rel); i += 1 {
		if rel[i] == '/' {
			strings.write_byte(&builder, '.')
		} else {
			strings.write_byte(&builder, rel[i])
		}
	}
	dotted := strings.to_string(builder)
	strings.builder_destroy(&builder)

	return base.intern(interner, dotted)
}

simple_hash :: proc(data: string) -> string {
	h: u64 = 14695981039346656037
	for i := 0; i < len(data); i += 1 {
		h = h ~ u64(data[i])
		h = h * 1099511628211
	}
	return fmt.tprintf("{:x}", h)
}

project_discovery_destroy :: proc(project: ^Project_Discovery) {
	for _, mi in project.modules {
		delete(mi.imports)
		delete(mi.exports)
	}
	delete(project.modules)
	delete(project.module_names)
}

// Register stdlib modules into the project discovery.
// Called after discover_project to add embedded stdlib modules as a fallback.
register_stdlib_modules :: proc(project: ^Project_Discovery, interner: ^base.Intern_Table) {
	for mod in STDLIB_MODULES {
		name_id := base.intern(interner, mod.name)
		if _, exists := project.modules[name_id]; exists {
			continue  // project-local module takes precedence
		}
		mi := Module_Info{
			name = name_id,
			path = mod.path,
			content_hash = simple_hash(mod.source),
			source = mod.source,
			imports = make([dynamic]base.Deferred_Import, 0, 8),
			exports = make([dynamic]Export_Info, 0, 16),
		}
		project.modules[name_id] = mi
		append(&project.module_names, name_id)
	}
}


