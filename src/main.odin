package camp

import "core:fmt"
import "core:os"
import "core:strconv"

import "camp:base"
import "camp:build"
import "camp:diagnostics"
import "camp:format"
import "camp:lsp"

VERSION :: "0.0.1"

main :: proc() {
	raw_args := os.args
	args := make([dynamic]string, 0, len(raw_args))
	defer delete(args)
	locked := false
	frozen := false
	for a in raw_args {
		if a == "--json" {
			diagnostics.set_json_mode(true)
		} else if a == "--locked" {
			locked = true
		} else if a == "--frozen" {
			frozen = true
		} else {
			append(&args, a)
		}
	}

	if len(args) < 2 {
		fmt.printfln("Camp compiler v{}", VERSION)
		fmt.println("Usage: camp <command> [options] <file>")
		fmt.println("Commands: build, test, fmt, check, doc, run, lsp, add, update, init")
		fmt.println("Global flags: --json, --locked, --frozen")
		os.exit(1)
	}

	if args[1] == "--explain" {
		if len(args) > 2 {
			diagnostics.run_explain(args[2])
		} else {
			diagnostics.list_codes()
		}
		return
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

	thread_count := 1
	if threads_str := os.get_env_alloc("CAMP_THREADS", context.allocator); threads_str != "" {
		if n, ok := strconv.parse_int(threads_str); ok {
			thread_count = n
		}
	}
	// Parse -o/--output flag and detect file vs project mode
	file_path: string
	output_path: string
	{
		i := 0
		for i < len(remaining_args) {
			a := remaining_args[i]
			if a == "-o" || a == "--output" {
				if i + 1 < len(remaining_args) {
					output_path = remaining_args[i + 1]
					i += 1
				} else {
					fmt.eprintln("error: -o requires a path argument")
					os.exit(2)
				}
			} else if len(a) > 0 && a[0] != '-' && file_path == "" {
				file_path = a
			}
			i += 1
		}
	}

	result: build.Build_Result
	switch cmd {
	case .Build:
		if file_path != "" {
			result = build.run_build_single(file_path, thread_count, output_path)
		} else {
			result = build.run_build_project(thread_count, output_path)
		}
	case .Test:
		// Detect if any arg looks like a file path (has .camp extension)
		has_file := false
		for a in remaining_args {
			if len(a) > 0 && a[0] != '-' {
				has_file = true
				break
			}
		}
		if has_file {
			result = build.run_test(remaining_args)
		} else {
			filter := ""
			verbose := false
			i := 0
			for i < len(remaining_args) {
				if remaining_args[i] == "--filter" && i + 1 < len(remaining_args) {
					i += 1
					filter = remaining_args[i]
				} else if remaining_args[i] == "--verbose" {
					verbose = true
				}
				i += 1
			}
			result = build.run_test_project(filter, verbose)
		}
	case .Fmt:
		format.run_fmt(remaining_args)
		return
	case .Check:
		if file_path != "" {
			result = build.run_check(remaining_args)
		} else {
		result = build.run_check_project(thread_count)
		}
	case .Doc:
		result = build.run_doc(remaining_args)
	case .Lsp:
		lsp.lsp_main()
		return
	case .Run:
		result = build.run_run(remaining_args)
	case .Add:
		run_add(remaining_args)
		return
	case .Update:
		run_update(remaining_args)
		return
	case .Init:
		run_init(remaining_args)
		return
	}

	if failed, is_failed := result.(build.Build_Error); is_failed {
		os.exit(failed.code)
	}
}

