package format

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "camp:diagnostics"

Run_Error :: struct {
	message: string,
	code:    int,
}

Run_Result :: union {
	bool,
	Run_Error,
}

run_fmt :: proc(args: []string) -> Run_Result {
	check_mode := false
	stdin_mode := false
	file_args: [dynamic]string
	defer delete(file_args)

	for arg in args {
		if arg == "--check" {
			check_mode = true
		} else if arg == "--stdin" {
			stdin_mode = true
		} else if len(arg) > 0 && arg[0] == '-' {
			fmt.eprintfln("unknown flag: %s", arg)
			return Run_Error{message = fmt.tprintf("unknown flag: %s", arg), code = 2}
		} else {
			append(&file_args, arg)
		}
	}

	if stdin_mode {
		if len(file_args) > 0 {
			fmt.eprintfln("--stdin cannot be combined with file arguments")
			return Run_Error{message = "--stdin cannot be combined with file arguments", code = 2}
		}
		return run_fmt_stdin(check_mode)
	}

	if len(file_args) == 0 {
		append(&file_args, ".")
	}

	changed := false
	had_errors := false

	for path in file_args {
		stat, err := os.stat(path, context.allocator)
		if err != nil {
			fmt.eprintfln("error accessing %s: %v", path, err)
			had_errors = true
			continue
		}
		defer os.file_info_delete(stat, context.allocator)

		if stat.type == .Directory {
			dir_changed, dir_errors := run_fmt_dir(path, check_mode)
			changed = changed || dir_changed
			had_errors = had_errors || dir_errors
		} else {
			file_changed, file_error := run_fmt_file(path, check_mode)
			changed = changed || file_changed
			if file_error {
				had_errors = true
			}
		}
	}

	if had_errors {
		return Run_Error{message = "formatting errors", code = 1}
	}
	if changed {
		return Run_Error{message = "files would be reformatted", code = 1}
	}

	return true
}

run_fmt_stdin :: proc(check_mode: bool) -> Run_Result {
	source_bytes, err := os.read_entire_file_from_file(os.stdin, context.allocator)
	if err != nil {
		fmt.eprintfln("error reading stdin: %v", err)
		return Run_Error{message = fmt.tprintf("error reading stdin: %v", err), code = 1}
	}
	defer delete(source_bytes, context.allocator)

	source := string(source_bytes)
	result := format(source, "<stdin>", context.allocator)
	defer fmt_cleanup_result(&result)

	if len(result.diagnostics) > 0 {
		render_fmt_diagnostics(result.diagnostics[:], "<stdin>", source)
		return Run_Error{message = "formatting errors in stdin", code = 1}
	}

	if check_mode {
		if result.output != source {
			fmt.eprintfln("stdin would be reformatted")
			return Run_Error{message = "stdin would be reformatted", code = 1}
		}
	} else {
		fmt.print(result.output)
	}

	return true
}

run_fmt_dir :: proc(dir_path: string, check_mode: bool) -> (changed: bool, had_errors: bool) {
	w := os.walker_create(dir_path)
	defer os.walker_destroy(&w)

	for info in os.walker_walk(&w) {
		if path, err := os.walker_error(&w); err != nil {
			fmt.eprintfln("error walking %s: %v", path, err)
			had_errors = true
			continue
		}

		if info.type != .Regular {
			continue
		}

		if filepath.ext(info.fullpath) == ".camp" {
			file_changed, file_error := run_fmt_file(info.fullpath, check_mode)
			changed = changed || file_changed
			if file_error {
				had_errors = true
			}
		}
	}

	return
}

run_fmt_file :: proc(file_path: string, check_mode: bool) -> (changed: bool, had_errors: bool) {
	source_bytes, err := os.read_entire_file(file_path, context.allocator)
	if err != nil {
		fmt.eprintfln("error reading %s: %v", file_path, err)
		return false, true
	}
	defer delete(source_bytes, context.allocator)

	source := string(source_bytes)
	result := format(source, file_path, context.allocator)
	defer fmt_cleanup_result(&result)

	if len(result.diagnostics) > 0 {
		render_fmt_diagnostics(result.diagnostics[:], file_path, source)
		return false, true
	}

	if result.output == source {
		return false, false
	}

	if check_mode {
		fmt.eprintfln("%s: would reformat", file_path)
		return true, false
	}

	err = os.write_entire_file(file_path, transmute([]byte)result.output)
	if err != nil {
		fmt.eprintfln("error writing %s: %v", file_path, err)
		return false, true
	}

	return true, false
}

render_fmt_diagnostics :: proc(diags: []diagnostics.Diagnostic, file_path: string, source: string) {
	collector: diagnostics.Diagnostic_Collector
	diagnostics.diag_collector_init(&collector)
	defer diagnostics.diag_collector_destroy(&collector)

	for d in diags {
		diagnostics.collector_add_diag(&collector, d)
	}

	diagnostics.render_all(&collector, file_path, source)
}

fmt_cleanup_result :: proc(result: ^Format_Result) {
	delete(result.output)
	for &d in result.diagnostics {
		delete(d.labels)
		delete(d.hints)
	}
	delete(result.diagnostics)
}


