package camp

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

Cache_Entry :: struct {
	hash:      string,
	file_path: string,
}

cache_dir :: proc() -> string {
	xdg := os.get_env_alloc("XDG_CACHE_HOME", context.allocator)
	if len(xdg) > 0 {
		result, _ := filepath.join({xdg, "camp"}, context.allocator)
		delete(xdg, context.allocator)
		return result
	}
	home := os.get_env_alloc("HOME", context.allocator)
	result, _ := filepath.join({home, ".cache", "camp"}, context.allocator)
	delete(home, context.allocator)
	return result
}

cache_ensure_dir :: proc() -> string {
	dir := cache_dir()
	os.make_directory_all(dir)
	return dir
}

cache_write :: proc(key: string, ext: string, data: []byte) -> bool {
	dir := cache_ensure_dir()
	path, _ := filepath.join({dir, fmt.tprintf("{}{}", key, ext)}, context.allocator)
	err := os.write_entire_file_from_bytes(path, data)
	return err == nil
}

cache_read :: proc(key: string, ext: string, allocator: mem.Allocator) -> ([]byte, bool) {
	dir := cache_dir()
	path, _ := filepath.join({dir, fmt.tprintf("{}{}", key, ext)}, allocator)

	data, err := os.read_entire_file(path, allocator)
	if err != nil {
		return nil, false
	}
	return data, true
}

cache_key_for_file :: proc(mi: ^Module_Info) -> string {
	return mi.content_hash
}

cache_key_for_typecheck :: proc(mi: ^Module_Info, project: ^Project_Discovery, interner: ^Intern_Table) -> string {
	builder: strings.Builder
	strings.builder_init_len_cap(&builder, 0, 256)

	strings.write_string(&builder, mi.content_hash)

	import_hashes: [dynamic]string
	import_hashes = make([dynamic]string, 0, len(mi.imports))
	defer delete(import_hashes)

	for imp in mi.imports {
		if dep, ok := project.modules[imp.module]; ok {
			append(&import_hashes, dep.content_hash)
		}
	}

	simple_sort_strings(&import_hashes)

	for h in import_hashes {
		strings.write_string(&builder, h)
	}

	combined := strings.to_string(builder)
	strings.builder_destroy(&builder)

	return simple_hash(combined)
}

simple_sort_strings :: proc(arr: ^[dynamic]string) {
	for i := 0; i < len(arr) - 1; i += 1 {
		for j := i + 1; j < len(arr); j += 1 {
			if arr[j] < arr[i] {
				arr[i], arr[j] = arr[j], arr[i]
			}
		}
	}
}
