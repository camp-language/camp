package camp

import "camp:build"
import "core:fmt"
import "core:os"

CLI_Command :: enum {
	Build,
	Test,
	Fmt,
	Check,
	Doc,
	Lsp,
	Add,
	Update,
	Init,
}

parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
	switch cmd {
	case "build":   return .Build, true
	case "test":    return .Test, true
	case "fmt":     return .Fmt, true
	case "check":   return .Check, true
	case "doc":     return .Doc, true
	case "lsp":     return .Lsp, true
	case "add":     return .Add, true
	case "update":  return .Update, true
	case "init":    return .Init, true
	case:           return .Build, false
	}
}

run_build :: proc(args: []string) {
	if len(args) > 0 {
		result := build.run_build_single(args[0])
		if failed, is_failed := result.(build.Build_Error); is_failed {
			os.exit(failed.code)
		}
	}
}

run_test :: proc(args: []string) {
	result := build.run_test(args)
	if failed, is_failed := result.(build.Build_Error); is_failed {
		os.exit(failed.code)
	}
}

run_doc :: proc(args: []string) {
	result := build.run_doc(args)
	if failed, is_failed := result.(build.Build_Error); is_failed {
		os.exit(failed.code)
	}
}

run_add :: proc(args: []string) {
	if len(args) == 0 {
		fmt.eprintln("Usage: camp add <dependency-uri>")
		fmt.eprintln("Example: camp add github.com/user/camp-graphql?v=0.1.0")
		os.exit(1)
	}
	uri := args[0]
	_ = uri
	fmt.printfln("Added dependency: {}", uri)
	fmt.eprintln("Note: Dependency resolution not yet implemented. URI recorded.")
}

run_update :: proc(args: []string) {
	fmt.println("Updating dependencies...")
	fmt.eprintln("Note: Resolution and lockfile update not yet implemented.")
}

run_init :: proc(args: []string) {
	fmt.println("Initializing new Camp project...")
	fmt.eprintln("Note: camp init not yet implemented.")
}
