package camp

import "core:fmt"
import "core:os"

VERSION :: "0.0.1"

main :: proc() {
	args := os.args
	if len(args) < 2 {
		fmt.printfln("Camp compiler v{}", VERSION)
		fmt.println("Usage: camp <command> [options] <file>")
		fmt.println("Commands: build, test, fmt, check")
		os.exit(1)
	}

	cmd, ok := parse_command(args[1])
	if !ok {
		fmt.printfln("error: unknown command '{}'", args[1])
		fmt.println("Commands: build, test, fmt, check")
		os.exit(1)
	}

	remaining_args := args[2:]
	switch cmd {
	case .Build: run_build(remaining_args)
	case .Test:  fmt.println("TODO: camp test")
	case .Fmt:   fmt.println("TODO: camp fmt")
	case .Check: fmt.println("TODO: camp check")
	}
}
