package camp

import "core:fmt"
import "core:os"

VERSION :: "0.0.1"

main :: proc() {
	args := os.args
	if len(args) < 2 {
		fmt.printfln("Camp compiler v{}", VERSION)
		fmt.println("Usage: camp <command> [options] <file>")
		fmt.println("Commands: build, test, fmt, check, lsp")
		os.exit(1)
	}

	cmd, ok := parse_command(args[1])
	if !ok {
		collector: Diagnostic_Collector
		diag_collector_init(&collector)
		collector_add_diag(&collector, diag_unknown_command(args[1]))
		render_all(&collector, "", "")
		diag_collector_destroy(&collector)
		os.exit(1)
	}

	remaining_args := args[2:]
	switch cmd {
	case .Build: run_build(remaining_args)
	case .Test:  fmt.println("TODO: camp test")
	case .Fmt:   run_fmt(remaining_args)
	case .Check: fmt.println("TODO: camp check")
	case .Lsp:   lsp_main()
	}
}
