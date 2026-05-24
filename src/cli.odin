package camp

import "camp:build"
import "core:os"

CLI_Command :: enum {
	Build,
	Test,
	Fmt,
	Check,
	Lsp,
}

parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
	switch cmd {
	case "build": return .Build, true
	case "test":  return .Test, true
	case "fmt":   return .Fmt, true
	case "check": return .Check, true
	case "lsp":   return .Lsp, true
	case:         return .Build, false
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
