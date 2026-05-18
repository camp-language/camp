package camp

import "core:fmt"
import "core:os"
import "core:path/filepath"

CLI_Command :: enum {
	Build,
	Test,
	Fmt,
	Check,
}

parse_command :: proc(cmd: string) -> (CLI_Command, bool) {
	switch cmd {
	case "build": return .Build, true
	case "test":  return .Test, true
	case "fmt":   return .Fmt, true
	case "check": return .Check, true
	case:         return .Build, false
	}
}

run_build :: proc(args: []string) {
	file_path := "main.camp"
	if len(args) > 0 {
		file_path = args[0]
	}

	if filepath.ext(file_path) != ".camp" {
		fmt.printfln("error: expected .camp file, got {}", file_path)
		os.exit(1)
	}

	collector: Error_Collector
	collector_init(&collector)
	defer collector_destroy(&collector)

	fmt.printfln("compiling {}...", file_path)
	fmt.println("TODO: implement compilation pipeline")
}
