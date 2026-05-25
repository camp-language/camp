package build

import "core:testing"

EXPECTED_STDLIB_MODULE_COUNT :: 43

ALL_MODULE_NAMES :: []string{
	"Result",
	"Bool",
	"Str",
	"List",
	"Iter",
	"Map",
	"Set",
	"Display",
	"Num.I64",
	"Num.I32",
	"Num.I16",
	"Num.I8",
	"Num.U64",
	"Num.U32",
	"Num.U16",
	"Num.U8",
	"Num.F64",
	"Num.F32",
	"Bytes",
	"Eq",
	"Ord",
	"Hash",
	"Debug",
	"Default",
	"IntoIter",
	"FromIter",
	"From",
	"TryFrom",
	"Console",
	"Throw",
	"File",
	"Env",
	"Time",
	"Random",
	"Log",
	"Path",
	"Duration",
	"Fmt",
	"Uuid",
	"Json",
	"Regex",
	"Uri",
	"Base64",
}

// substring check without importing core:strings
_contains :: proc(s, substr: string) -> bool {
	if len(substr) == 0 do return true
	if len(substr) > len(s) do return false
	for i := 0; i <= len(s) - len(substr); i += 1 {
		if s[i:i + len(substr)] == substr {
			return true
		}
	}
	return false
}

@(test)
test_stdlib_modules_count :: proc(t: ^testing.T) {
	testing.expectf(t, len(STDLIB_MODULES) == EXPECTED_STDLIB_MODULE_COUNT,
		"expected %d stdlib modules, got %d", EXPECTED_STDLIB_MODULE_COUNT, len(STDLIB_MODULES))
}

@(test)
test_stdlib_lookup_known_modules :: proc(t: ^testing.T) {
	for name in ALL_MODULE_NAMES {
		mod, ok := stdlib_lookup(name)
		testing.expectf(t, ok, "stdlib_lookup(%q) should return true", name)
		if ok {
			testing.expectf(t, len(mod.source) > 0,
				"stdlib_lookup(%q).source should be non-empty", name)
		}
	}
}

@(test)
test_stdlib_lookup_unknown_module :: proc(t: ^testing.T) {
	_, ok := stdlib_lookup("NonExistent")
	testing.expect(t, !ok)
}

@(test)
test_stdlib_is_module_known :: proc(t: ^testing.T) {
	for name in ALL_MODULE_NAMES {
		testing.expectf(t, stdlib_is_module(name),
			"stdlib_is_module(%q) should return true", name)
	}
}

@(test)
test_stdlib_is_module_unknown :: proc(t: ^testing.T) {
	testing.expect(t, !stdlib_is_module("NonExistent"))
}

@(test)
test_stdlib_modules_unique_names :: proc(t: ^testing.T) {
	seen := make(map[string]bool)
	defer delete(seen)

	for mod in STDLIB_MODULES {
		_, exists := seen[mod.name]
		testing.expectf(t, !exists, "duplicate module name: %q", mod.name)
		seen[mod.name] = true
	}
}

@(test)
test_stdlib_modules_nonempty_source :: proc(t: ^testing.T) {
	for mod in STDLIB_MODULES {
		testing.expectf(t, len(mod.source) > 0,
			"module %q has empty source", mod.name)
	}
}

@(test)
test_stdlib_modules_nonempty_path :: proc(t: ^testing.T) {
	for mod in STDLIB_MODULES {
		testing.expectf(t, len(mod.path) > 0,
			"module %q has empty path", mod.name)
	}
}

@(test)
test_stdlib_modules_path_format :: proc(t: ^testing.T) {
	for mod in STDLIB_MODULES {
		has_prefix := len(mod.path) >= 7 && mod.path[:7] == "stdlib/"
		has_suffix := len(mod.path) >= 5 && mod.path[len(mod.path) - 5:] == ".camp"
		testing.expectf(t, has_prefix,
			"module %q path %q should start with \"stdlib/\"", mod.name, mod.path)
		testing.expectf(t, has_suffix,
			"module %q path %q should end with \".camp\"", mod.name, mod.path)
	}
}

@(test)
test_stdlib_lookup_result_source :: proc(t: ^testing.T) {
	mod, ok := stdlib_lookup("Result")
	testing.expect(t, ok)
	testing.expectf(t, _contains(mod.source, "@Result(a, e): pub [Ok(a) | Err(e)]"),
		"Result source should contain @Result annotation")
}

@(test)
test_stdlib_lookup_bool_source :: proc(t: ^testing.T) {
	mod, ok := stdlib_lookup("Bool")
	testing.expect(t, ok)
	testing.expectf(t, _contains(mod.source, "pub not"),
		"Bool source should contain \"pub not\"")
}

@(test)
test_stdlib_lookup_random_source :: proc(t: ^testing.T) {
	mod, ok := stdlib_lookup("Random")
	testing.expect(t, ok)
	testing.expectf(t, _contains(mod.source, "effect Random!"),
		"Random source should contain \"effect Random!\"")
}
