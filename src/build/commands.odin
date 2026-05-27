package build

import "camp:camp_toml"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// ---- camp init ----

run_init :: proc(args: []string) {
	package_name := "github.com/user/unknown"
	if len(args) > 0 {package_name = args[0]}

	cwd := "."
	toml_path, _ := filepath.join({cwd, "camp.toml"}, context.temp_allocator)

	if os.exists(toml_path) {
		fmt.eprintfln("camp.toml already exists")
		os.exit(1)
	}

	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "[package]\n")
	fmt.sbprintf(&b, "name = \"{}\"\n", package_name)
	fmt.sbprintf(&b, "version = \"0.0.0\"\n\n")
	fmt.sbprintf(&b, "[dependencies]\n\n")
	fmt.sbprintf(&b, "[dev-dependencies]\n")
	content := strings.to_string(b)

	write_err := os.write_entire_file(toml_path, transmute([]byte)content)
	if write_err != nil {
		fmt.eprintfln("Failed to create camp.toml")
		os.exit(1)
	}

	fmt.printfln("Created camp.toml with package {}", package_name)
	src_path, _ := filepath.join({cwd, "src"}, context.temp_allocator)
	_ = os.make_directory(src_path)
}

// ---- camp add ----

run_add :: proc(args: []string) {
	if len(args) == 0 {
		fmt.eprintln("Usage: camp add <dependency-uri>")
		fmt.eprintln("Example: camp add github.com/user/camp-graphql?v=0.1.0")
		os.exit(1)
	}

	uri := args[0]
	root := find_project_root(".", context.temp_allocator)
	if root == "" {
		fmt.eprintln("Error: no Camp project found")
		os.exit(1)
	}

	toml_path, _ := filepath.join({root, "camp.toml"}, context.temp_allocator)
	toml_data, read_err := os.read_entire_file(toml_path, context.temp_allocator)
	if read_err != nil {
		fmt.eprintln("Error: camp.toml not found — run `camp init` first")
		os.exit(1)
	}
	defer delete(toml_data, context.temp_allocator)

	manifest := camp_toml.parse(string(toml_data), context.temp_allocator)
	alias := _alias_from_uri(uri)
	source, _ := parse_dep_uri(uri)

	// Check for duplicate
	for dep in manifest.dependencies {
		if dep.uri == uri || dep.alias == alias {
			fmt.printfln("Dependency '{}' already exists", alias)
			return
		}
	}

	// Try to resolve tags
	tags := fetch_git_tags(source)
	if len(tags) > 0 {
		if idx := strings.index(uri, "?v="); idx >= 0 {
			ver_str := uri[idx + 3:]
			if v, sv_ok := semver_parse(ver_str); sv_ok {
				best := semver_best_match(tags, v)
				if best != "" {
					fmt.printfln("Resolved {} → {} ({})", alias, source, best)
				}
			}
		}
	} else {
		fmt.printfln("Note: could not fetch tags for {} (network required)", source)
	}

	// Append to camp.toml
	lines := strings.split_lines(string(toml_data), context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	injected := false
	for line in lines {
		fmt.sbprintf(&b, "{}\n", line)
		if !injected && strings.has_prefix(strings.trim_space(line), "[dependencies]") {
			fmt.sbprintf(&b, "{} = \"{}\"\n", alias, uri)
			injected = true
		}
	}
	_ = os.write_entire_file(toml_path, transmute([]byte)strings.to_string(b))

	fmt.printfln("Added dependency: {}", uri)
}

// ---- camp update ----

run_update :: proc(args: []string) {
	root := find_project_root(".", context.temp_allocator)
	if root == "" {
		fmt.eprintln("Error: no Camp project found")
		os.exit(1)
	}

	toml_path, _ := filepath.join({root, "camp.toml"}, context.temp_allocator)
	toml_data, read_err := os.read_entire_file(toml_path, context.temp_allocator)
	if read_err != nil {
		fmt.eprintln("Error: camp.toml not found")
		os.exit(1)
	}
	defer delete(toml_data, context.temp_allocator)

	manifest := camp_toml.parse(string(toml_data), context.temp_allocator)
	lock, _ := lock_read(root, context.temp_allocator)

	fmt.println("Resolving dependencies...")
	resolved_count := 0

	for dep in manifest.dependencies {
		source, _ := parse_dep_uri(dep.uri)
		tags := fetch_git_tags(source)
		if len(tags) > 0 {
			ver_str := ""
			if idx := strings.index(dep.uri, "?v="); idx >= 0 {
				ver_str = dep.uri[idx + 3:]
			}
			if len(ver_str) > 0 {
				if v, sv_ok := semver_parse(ver_str); sv_ok {
					best := semver_best_match(tags, v)
					if best != "" {
						rev, rev_ok := resolve_tag_to_rev(source, best)
						if rev_ok {
							entry := Lock_Entry {
								name    = dep.alias,
								source  = source,
								version = best,
								rev     = rev,
								hash    = rev,
							}
							found := false
							for i in 0 ..< len(lock.packages) {
								if lock.packages[i].source == source {
									lock.packages[i] = entry
									found = true
									break
								}
							}
							if !found {append(&lock.packages, entry)}
							fmt.printfln("  {} → {} [{}]", source, best, rev[:8])
							resolved_count += 1
						}
					}
				}
			}
		}
	}

	if resolved_count > 0 || len(lock.packages) > 0 {
		lock_write(lock, root, context.temp_allocator)
		fmt.printfln("Updated camp.lock ({} packages)", len(lock.packages))
	} else {
		fmt.println("No dependencies to update.")
	}
}

// ---- Helpers ----

_alias_from_uri :: proc(uri: string) -> string {
	source, _ := parse_dep_uri(uri)
	last_slash := strings.last_index(source, "/")
	if last_slash >= 0 {return source[last_slash + 1:]}
	return source
}

