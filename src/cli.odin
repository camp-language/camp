package camp

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
	thread_count := 1
	filtered := make([dynamic]string, 0, len(args))
	i := 0
	for i < len(args) {
		if args[i] == "--threads" && i + 1 < len(args) {
			i += 1
			val := args[i]
			n: int = 0
			for c in val {
				if c >= '0' && c <= '9' {
					n = n * 10 + int(c - '0')
				} else {
					break
				}
			}
			if n > 0 {
				thread_count = n
			}
			i += 1
		} else {
			append(&filtered, args[i])
			i += 1
		}
	}
	defer delete(filtered)

	single_file := len(filtered) > 0

	if single_file {
		run_build_single(filtered[0])
		return
	}

	run_build_project(thread_count)
}


