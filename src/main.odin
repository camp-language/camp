package camp

import "core:fmt"
import "core:os"

import "camp:base"
import "camp:diagnostics"
import "camp:build"
import "camp:format"
import "camp:lsp"

VERSION :: "0.0.1"

main :: proc() {
	raw_args := os.args
	args := make([dynamic]string, 0, len(raw_args))
	defer delete(args)
	for a in raw_args {
		if a == "--json" {
			diagnostics.set_json_mode(true)
		} else {
			append(&args, a)
		}
	}

	if len(args) < 2 {
		fmt.printfln("Camp compiler v{}", VERSION)
		fmt.println("Usage: camp <command> [options] <file>")
		fmt.println("Commands: build, test, fmt, check, explain, lsp")
		fmt.println("Global flags: --json (machine-readable diagnostics on stdout)")
		os.exit(1)
	}

	cmd, ok := parse_command(args[1])
	if !ok {
		collector: diagnostics.Diagnostic_Collector
		diagnostics.diag_collector_init(&collector)
		diagnostics.collector_add_diag(&collector, diagnostics.diag_unknown_command(args[1]))
		diagnostics.render_all(&collector, "", "")
		diagnostics.diag_collector_destroy(&collector)
		os.exit(1)
	}

	remaining_args := args[2:]
	result: build.Build_Result
	switch cmd {
	case .Build:
		file_path := len(remaining_args) > 0 ? remaining_args[0] : ""
		result = build.run_build_single(file_path)
	case .Test:
		result = build.run_test(remaining_args)
	case .Fmt:
		format.run_fmt(remaining_args)
		return
	case .Check:
		result = build.run_check(remaining_args)
	case .Lsp:
		lsp.lsp_main()
		return
	case .Explain:
		os.exit(diagnostics.run_explain(remaining_args))
	}

	if failed, is_failed := result.(build.Build_Error); is_failed {
		os.exit(failed.code)
	}
}
