package camp

import "camp:camp_toml"
import "core:testing"
import "core:strings"

@(test)
test_camp_toml_minimal :: proc(t: ^testing.T) {
	input := `[package]
name = "github.com/user/my-app"
version = "0.1.0"
`
	manifest := camp_toml.parse(input, context.temp_allocator)

	testing.expect(t, manifest.pkg.name == "github.com/user/my-app")
	testing.expect(t, manifest.pkg.version == "0.1.0")
	testing.expect(t, manifest.pkg.description == "")
	testing.expect(t, len(manifest.dependencies) == 0)
	testing.expect(t, len(manifest.dev_dependencies) == 0)
}

@(test)
test_camp_toml_full :: proc(t: ^testing.T) {
	input := `[package]
name = "github.com/user/camp-graphql"
version = "0.1.0"
description = "A Camp GraphQL framework"
licenses = ["MIT", "Apache-2.0"]

[dependencies]
graphql = "github.com/user/camp-graphql?v=0.1.0"
http = "github.com/user/camp-http?v=2.0.0"

[dev-dependencies]
test-utils = "github.com/user/test-utils?v=0.3.0"
`
	manifest := camp_toml.parse(input, context.temp_allocator)

	testing.expect(t, manifest.pkg.name == "github.com/user/camp-graphql")
	testing.expect(t, manifest.pkg.version == "0.1.0")
	testing.expect(t, manifest.pkg.description == "A Camp GraphQL framework")
	testing.expect(t, len(manifest.pkg.licenses) == 2)
	testing.expect(t, manifest.pkg.licenses[0] == "MIT")
	testing.expect(t, manifest.pkg.licenses[1] == "Apache-2.0")

	testing.expect(t, len(manifest.dependencies) == 2)
	testing.expect(t, manifest.dependencies[0].alias == "graphql")
	testing.expect(t, manifest.dependencies[0].uri == "github.com/user/camp-graphql?v=0.1.0")
	testing.expect(t, manifest.dependencies[1].alias == "http")
	testing.expect(t, manifest.dependencies[1].uri == "github.com/user/camp-http?v=2.0.0")

	testing.expect(t, len(manifest.dev_dependencies) == 1)
	testing.expect(t, manifest.dev_dependencies[0].alias == "test-utils")
	testing.expect(t, manifest.dev_dependencies[0].uri == "github.com/user/test-utils?v=0.3.0")
}

@(test)
test_camp_toml_validation_snake_case :: proc(t: ^testing.T) {
	input := `[package]
name = "github.com/user/test"
version = "0.1.0"

[dependencies]
GraphQL = "github.com/user/test?v=0.1.0"
`
	manifest := camp_toml.parse(input, context.temp_allocator)
	errors := camp_toml.validate(manifest, context.temp_allocator)
	defer delete(errors)

	found := false
	for err in errors {
		if strings.contains(err.msg, "snake_case") {
			found = true
			testing.expect(t, strings.contains(err.msg, "GraphQL"))
		}
	}
	testing.expect(t, found)
}

@(test)
test_camp_toml_validation_missing_name :: proc(t: ^testing.T) {
	input := `[package]
version = "0.1.0"
`
	manifest := camp_toml.parse(input, context.temp_allocator)
	errors := camp_toml.validate(manifest, context.temp_allocator)
	defer delete(errors)

	testing.expect(t, len(errors) > 0)
	found := false
	for err in errors {
		if strings.contains(err.msg, "name") {found = true}
	}
	testing.expect(t, found)
}

@(test)
test_camp_toml_snake_case_valid :: proc(t: ^testing.T) {
	inputs := []string{"my_dep", "my_dep_2", "snake_case_alias", "a"}
	for inp in inputs {
		testing.expect(t, camp_toml._is_snake_case(inp), inp)
	}
}

@(test)
test_camp_toml_snake_case_invalid :: proc(t: ^testing.T) {
	inputs := []string{"MyDep", "my-dep", "a__b", "_leading", "trailing_", "1start"}
	for inp in inputs {
		testing.expect(t, !camp_toml._is_snake_case(inp), inp)
	}
}
