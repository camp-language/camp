package camp

import "camp:build"

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
	Run,
}

parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
	switch cmd {
	case "build":
		return .Build, true
	case "test":
		return .Test, true
	case "fmt":
		return .Fmt, true
	case "check":
		return .Check, true
	case "doc":
		return .Doc, true
	case "lsp":
		return .Lsp, true
	case "add":
		return .Add, true
	case "update":
		return .Update, true
	case "init":
		return .Init, true
	case "run":
		return .Run, true
	case:
		return .Build, false
	}
}

run_add :: proc(args: []string) {
	build.run_add(args)
}

run_update :: proc(args: []string) {
	build.run_update(args)
}

run_init :: proc(args: []string) {
	build.run_init(args)
}

