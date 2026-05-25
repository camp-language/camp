package build

import "camp:base"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

Cache_Entry :: struct {
	hash:      string,
	file_path: string,
}

MODULE_MANIFEST_MAGIC :u32 : 0x434D4D46
MODULE_MANIFEST_VERSION :u32 : 4

Module_Manifest :: struct {
	content_hash:  string,
	module_name:   string,
	imports:       [dynamic]Manifest_Import,
	exports:       [dynamic]Manifest_Export,
}

Manifest_Import :: struct {
	module:   string,
	names:    [dynamic]string,
	alias:    string,
}

Manifest_Export :: struct {
	name:         string,
	kind:         Export_Kind,
	is_pub:       bool,
	pub_variants: bool,
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

cache_has :: proc(key: string, ext: string) -> bool {
	dir := cache_dir()
	path, _ := filepath.join({dir, fmt.tprintf("{}{}", key, ext)}, context.allocator)
	_, err := os.stat(path, context.allocator)
	delete(path, context.allocator)
	return err == nil
}

cache_write :: proc(key: string, ext: string, data: []byte) -> bool {
	dir := cache_ensure_dir()
	path, _ := filepath.join({dir, fmt.tprintf("{}{}", key, ext)}, context.allocator)
	err := os.write_entire_file_from_bytes(path, data)
	delete(path, context.allocator)
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

cache_key_for_typecheck :: proc(mi: ^Module_Info, project: ^Project_Discovery, interner: ^base.Intern_Table) -> string {
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

manifest_destroy :: proc(manifest: ^Module_Manifest) {
	for &imp in manifest.imports {
		delete(imp.names)
	}
	delete(manifest.imports)
	delete(manifest.exports)
}

serialize_manifest :: proc(manifest: Module_Manifest, allocator: mem.Allocator) -> []byte {
	buf: [dynamic]u8
	buf.allocator = allocator

	write_u32_le(&buf, MODULE_MANIFEST_MAGIC)
	write_u32_le(&buf, MODULE_MANIFEST_VERSION)

	write_string(&buf, manifest.content_hash)
	write_string(&buf, manifest.module_name)

	write_u32_le(&buf, u32(len(manifest.imports)))
	for imp in manifest.imports {
		write_string(&buf, imp.module)
		write_u32_le(&buf, u32(len(imp.names)))
		for name in imp.names {
			write_string(&buf, name)
		}
		write_string(&buf, imp.alias)
	}

	write_u32_le(&buf, u32(len(manifest.exports)))
	for exp in manifest.exports {
		write_string(&buf, exp.name)
		write_u16_le(&buf, u16(int(exp.kind)))
		append(&buf, bool_to_u8(exp.is_pub))
		append(&buf, bool_to_u8(exp.pub_variants))
	}

	return buf[:]
}

deserialize_manifest :: proc(data: []byte, allocator: mem.Allocator) -> (Module_Manifest, bool) {
	if len(data) < 8 {
		return Module_Manifest{}, false
	}

	pos: int = 0

	magic, ok := read_u32_le(data, &pos)
	if !ok || magic != MODULE_MANIFEST_MAGIC {
		return Module_Manifest{}, false
	}

	version_val, ok2 := read_u32_le(data, &pos)
	if !ok2 || version_val != MODULE_MANIFEST_VERSION {
		return Module_Manifest{}, false
	}

	manifest: Module_Manifest
	manifest.imports = make([dynamic]Manifest_Import, 0, 8)
	manifest.exports = make([dynamic]Manifest_Export, 0, 8)

	content_hash, str_ok1 := read_string(data, &pos, allocator)
	module_name, str_ok2 := read_string(data, &pos, allocator)
	if !str_ok1 || !str_ok2 {
		return Module_Manifest{}, false
	}
	manifest.content_hash = content_hash
	manifest.module_name = module_name

	num_imports_val, imp_cnt_ok := read_u32_le(data, &pos)
	if !imp_cnt_ok { manifest_destroy(&manifest); return Module_Manifest{}, false }
	num_imports := int(num_imports_val)
	for i := 0; i < num_imports; i += 1 {
		imp: Manifest_Import
		imp.names = make([dynamic]string, 0, 8)

		mod_str, mod_ok := read_string(data, &pos, allocator)
		if !mod_ok { manifest_destroy(&manifest); return Module_Manifest{}, false }
		imp.module = mod_str

		num_names_val, name_cnt_ok := read_u32_le(data, &pos)
		if !name_cnt_ok { manifest_destroy(&manifest); return Module_Manifest{}, false }
		num_names := int(num_names_val)
		for j := 0; j < num_names; j += 1 {
			name_str, name_ok := read_string(data, &pos, allocator)
			if !name_ok { manifest_destroy(&manifest); return Module_Manifest{}, false }
			append(&imp.names, name_str)
		}

		alias_str, alias_ok := read_string(data, &pos, allocator)
		if !alias_ok { manifest_destroy(&manifest); return Module_Manifest{}, false }
		imp.alias = alias_str

		append(&manifest.imports, imp)
	}

	num_exports_val, exp_cnt_ok2 := read_u32_le(data, &pos)
	if !exp_cnt_ok2 { manifest_destroy(&manifest); return Module_Manifest{}, false }
	num_exports := int(num_exports_val)
	for i := 0; i < num_exports; i += 1 {
		exp: Manifest_Export

		name_str, name_ok := read_string(data, &pos, allocator)
		if !name_ok { manifest_destroy(&manifest); return Module_Manifest{}, false }
		exp.name = name_str

		kind_val_u16, kind_ok := read_u16_le(data, &pos)
		if !kind_ok { manifest_destroy(&manifest); return Module_Manifest{}, false }
		kind_val := int(kind_val_u16)
		if kind_val > int(Export_Kind.Newtype) {
			manifest_destroy(&manifest)
			return Module_Manifest{}, false
		}
		exp.kind = Export_Kind(kind_val)

		if pos < len(data) {
			exp.is_pub = data[pos] != 0
			pos += 1
		}

		if pos < len(data) {
			exp.pub_variants = data[pos] != 0
			pos += 1
		}

		append(&manifest.exports, exp)
	}

	return manifest, true
}

build_manifest :: proc(mi: ^Module_Info, interner: ^base.Intern_Table) -> Module_Manifest {
	manifest: Module_Manifest
	manifest.content_hash = mi.content_hash
	manifest.module_name = base.intern_get(interner, mi.name)
	manifest.imports = make([dynamic]Manifest_Import, 0, len(mi.imports))
	manifest.exports = make([dynamic]Manifest_Export, 0, len(mi.exports))

	for imp in mi.imports {
		mi_imp: Manifest_Import
		mi_imp.module = base.intern_get(interner, imp.module)
		mi_imp.names = make([dynamic]string, 0, len(imp.names))
		for name in imp.names {
			append(&mi_imp.names, base.intern_get(interner, name))
		}
		if imp.alias != base.NO_NAME {
			mi_imp.alias = base.intern_get(interner, imp.alias)
		}
		append(&manifest.imports, mi_imp)
	}

	for exp in mi.exports {
		me: Manifest_Export
		me.name = base.intern_get(interner, exp.name)
		me.kind = exp.kind
		me.is_pub = exp.is_pub
		me.pub_variants = exp.pub_variants
		append(&manifest.exports, me)
	}

	return manifest
}

cache_write_manifest :: proc(mi: ^Module_Info, interner: ^base.Intern_Table) -> bool {
	manifest := build_manifest(mi, interner)
	data := serialize_manifest(manifest, context.allocator)

	key := cache_key_for_file(mi)
	ok := cache_write(key, ".manifest", data)

	manifest_destroy(&manifest)
	delete(data, context.allocator)

	return ok
}

cache_read_manifest :: proc(content_hash: string, allocator: mem.Allocator) -> (Module_Manifest, bool) {
	data, ok := cache_read(content_hash, ".manifest", allocator)
	if !ok {
		return Module_Manifest{}, false
	}
	manifest, des_ok := deserialize_manifest(data, allocator)
	delete(data, allocator)
	return manifest, des_ok
}

write_u32_le :: proc(buf: ^[dynamic]u8, val: u32) {
	append(buf, u8(val & 0xff))
	append(buf, u8((val >> 8) & 0xff))
	append(buf, u8((val >> 16) & 0xff))
	append(buf, u8((val >> 24) & 0xff))
}

write_u16_le :: proc(buf: ^[dynamic]u8, val: u16) {
	append(buf, u8(val & 0xff))
	append(buf, u8((val >> 8) & 0xff))
}

read_u32_le :: proc(data: []u8, pos: ^int) -> (value: u32, ok: bool) {
	if pos^ + 4 > len(data) {
		return 0, false
	}
	result :u32 = u32(data[pos^])
	result |= u32(data[pos^ + 1]) << 8
	result |= u32(data[pos^ + 2]) << 16
	result |= u32(data[pos^ + 3]) << 24
	pos^ += 4
	return result, true
}

read_u16_le :: proc(data: []u8, pos: ^int) -> (value: u16, ok: bool) {
	if pos^ + 2 > len(data) {
		return 0, false
	}
	result :u16 = u16(data[pos^])
	result |= u16(data[pos^ + 1]) << 8
	pos^ += 2
	return result, true
}

write_string :: proc(buf: ^[dynamic]u8, s: string) {
	write_u32_le(buf, u32(len(s)))
	for i := 0; i < len(s); i += 1 {
		append(buf, s[i])
	}
}

read_string :: proc(data: []u8, pos: ^int, allocator: mem.Allocator) -> (string, bool) {
	if pos^ + 4 > len(data) {
		return "", false
	}
	length_val, ok := read_u32_le(data, pos)
	if !ok { return "", false }
	length := int(length_val)
	if length > 4096 || pos^ + length > len(data) {
		return "", false
	}

	result_data := make([]u8, length, allocator)
	for i := 0; i < length; i += 1 {
		result_data[i] = data[pos^ + i]
	}
	pos^ += length

	return string(result_data), true
}

bool_to_u8 :: proc(b: bool) -> u8 {
	if b do return 1
	return 0
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
