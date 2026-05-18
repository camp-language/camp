package e2e

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

E2E_Test :: struct {
	category:      string,
	name:          string,
	camp_path:     string,
	expected_path: string,
}

Test_Result :: enum {
	Pass,
	Fail,
	Skip,
}

Test_Report :: struct {
	test:   E2E_Test,
	result: Test_Result,
	diff:   string,
}

discover_tests :: proc(root: string, filter: string) -> []E2E_Test {
	tests: [dynamic]E2E_Test
	tests.allocator = context.allocator

	categories, cat_err := os.read_all_directory_by_path(root, context.allocator)
	if cat_err != nil {
		return tests[:]
	}
	defer os.file_info_slice_delete(categories, context.allocator)

	for cat_info in categories {
		if cat_info.type != .Directory { continue }
		category := cat_info.name
		if category == "." || category == ".." { continue }

		cat_path, cat_err2 := filepath.join({root, category}, context.allocator)
		if cat_err2 != nil { continue }
		defer delete(cat_path, context.allocator)

		files, file_err := os.read_all_directory_by_path(cat_path, context.allocator)
		if file_err != nil { continue }
		defer os.file_info_slice_delete(files, context.allocator)

		for fi in files {
			if fi.type != .Regular { continue }
			if filepath.ext(fi.name) != ".camp" { continue }

			name := filepath.stem(fi.name)
			expected_name := fmt.tprintf("{}.expected.toml", name)
			expected_path, ep_err := filepath.join({cat_path, expected_name}, context.allocator)
			if ep_err != nil { continue }

			if !os.exists(expected_path) {
				delete(expected_path, context.allocator)
				continue
			}

			camp_file_path, cp_err := filepath.join({cat_path, fi.name}, context.allocator)
			if cp_err != nil {
				delete(expected_path, context.allocator)
				continue
			}

			category_name := fmt.tprintf("{}/{}", category, name)
			if filter != "" && !strings.contains(category_name, filter) {
				delete(camp_file_path, context.allocator)
				delete(expected_path, context.allocator)
				continue
			}

			cat_clone, _ := strings.clone(category, context.allocator)
			name_clone, _ := strings.clone(name, context.allocator)

			append(&tests, E2E_Test{
				category      = cat_clone,
				name          = name_clone,
				camp_path     = camp_file_path,
				expected_path = expected_path,
			})
		}
	}

	return tests[:]
}

run_test :: proc(test: E2E_Test, update: bool) -> Test_Report {
	report: Test_Report
	report.test = test

	tmp_base, tmp_err := filepath.join({"/tmp/camp-e2e", test.category, test.name}, context.allocator)
	if tmp_err != nil {
		report.result = .Fail
		report.diff = "  setup: could not build temp path"
		return report
	}
	defer delete(tmp_base, context.allocator)
	os.make_directory_all(tmp_base)

	camp_filename := fmt.tprintf("{}.camp", test.name)
	tmp_camp, tc_err := filepath.join({tmp_base, camp_filename}, context.allocator)
	if tc_err != nil {
		report.result = .Fail
		report.diff = "  setup: could not build camp temp path"
		return report
	}
	defer delete(tmp_camp, context.allocator)

	copy_err := os.copy_file(tmp_camp, test.camp_path)
	if copy_err != nil {
		report.result = .Fail
		report.diff = fmt.tprintf("  setup: could not copy camp file: {}", copy_err)
		return report
	}

	expected_data, read_err := os.read_entire_file(test.expected_path, context.allocator)
	if read_err != nil {
		report.result = .Fail
		report.diff = fmt.tprintf("  setup: could not read expected file: {}", read_err)
		return report
	}
	defer delete(expected_data, context.allocator)

	expected_dict := toml_parse(string(expected_data), context.allocator)
	defer delete(expected_dict.entries)

	args_val, has_args := toml_get(&expected_dict, "args")

	stdout_str: string
	stderr_str: string
	exit_code: int

	if has_args {
		#partial switch a in args_val {
		case string:
			stdout_str, stderr_str, exit_code = run_special_command(a, tmp_base, camp_filename)
		}
	}

	if !has_args {
		stdout_str, stderr_str, exit_code = run_camp_build(tmp_camp)
	}

	wasm_stdout: string
	wasm_stderr: string
	wasm_exit: int
	has_wasm := false

	_, has_wasm_exit := toml_get(&expected_dict, "wasm_exit")
	if has_wasm_exit && exit_code == 0 {
		has_wasm = true
		wasm_filename := fmt.tprintf("{}.wasm", test.name)
		tmp_wasm, tw_err := filepath.join({tmp_base, wasm_filename}, context.allocator)
		if tw_err != nil {
			has_wasm = false
		} else {
			defer delete(tmp_wasm, context.allocator)
			wasm_stdout, wasm_stderr, wasm_exit = run_wasmtime(tmp_wasm)
		}
	}

	diff_builder: strings.Builder
	strings.builder_init_none(&diff_builder, context.allocator)
	defer strings.builder_destroy(&diff_builder)

	passed := true

	expected_stdout_val, has_stdout := toml_get(&expected_dict, "stdout")
	if has_stdout {
		#partial switch s in expected_stdout_val {
		case string:
			actual_stdout := ensure_trailing_newline(stdout_str)
			if actual_stdout != s {
				passed = false
				write_string_diff(&diff_builder, "stdout", s, actual_stdout)
			}
		}
	}

	expected_stderr_val, has_stderr := toml_get(&expected_dict, "stderr")
	if has_stderr {
		#partial switch s in expected_stderr_val {
		case string:
			actual_stderr := ensure_trailing_newline(stderr_str)
			if actual_stderr != s {
				passed = false
				write_string_diff(&diff_builder, "stderr", s, actual_stderr)
			}
		}
	}

	expected_exit_val, has_exit := toml_get(&expected_dict, "exit")
	if has_exit {
		#partial switch e in expected_exit_val {
		case int:
			if exit_code != e {
				passed = false
				fmt.sbprintf(&diff_builder, "  exit: expected {}, got {}\n", e, exit_code)
			}
		}
	}

	if has_wasm {
		expected_wasm_exit_val, _ := toml_get(&expected_dict, "wasm_exit")
		#partial switch e in expected_wasm_exit_val {
		case int:
			if wasm_exit != e {
				passed = false
				fmt.sbprintf(&diff_builder, "  wasm_exit: expected {}, got {}\n", e, wasm_exit)
			}
		}

		expected_wasm_stdout_val, has_ws := toml_get(&expected_dict, "wasm_stdout")
		if has_ws {
			#partial switch s in expected_wasm_stdout_val {
			case string:
				actual_ws := ensure_trailing_newline(wasm_stdout)
				if actual_ws != s {
					passed = false
					write_string_diff(&diff_builder, "wasm_stdout", s, actual_ws)
				}
			}
		}

		expected_wasm_stderr_val, has_we := toml_get(&expected_dict, "wasm_stderr")
		if has_we {
			#partial switch s in expected_wasm_stderr_val {
			case string:
				actual_we := ensure_trailing_newline(wasm_stderr)
				if actual_we != s {
					passed = false
					write_string_diff(&diff_builder, "wasm_stderr", s, actual_we)
				}
			}
		}
	}

	if update {
		write_update_file(test.expected_path, stdout_str, stderr_str, exit_code, has_wasm, wasm_stdout, wasm_stderr, wasm_exit)
		passed = true
	}

	if passed {
		report.result = .Pass
	} else {
		report.result = .Fail
		report.diff = strings.to_string(diff_builder)
	}

	return report
}

ensure_trailing_newline :: proc(s: string) -> string {
	if len(s) > 0 && !strings.has_suffix(s, "\n") {
		b: strings.Builder
		strings.builder_init_none(&b, context.allocator)
		fmt.sbprintf(&b, "{}\n", s)
		result, _ := strings.clone(strings.to_string(b), context.allocator)
		strings.builder_destroy(&b)
		return result
	}
	return s
}

capture_output :: proc(data: []byte) -> string {
	s, _ := strings.clone(string(data), context.allocator)
	return s
}

run_camp_build :: proc(camp_path: string) -> (stdout: string, stderr: string, exit_code: int) {
	desc := os.Process_Desc{
		command = {"./camp", "build", camp_path},
	}
	state, stdout_data, stderr_data, err := os.process_exec(desc, context.allocator)
	if err != nil {
		return "", fmt.tprintf("failed to execute camp: {}", err), 1
	}
	defer delete(stdout_data, context.allocator)
	defer delete(stderr_data, context.allocator)

	exit_code = state.exit_code
	stdout = capture_output(stdout_data)
	stderr = capture_output(stderr_data)
	return
}

run_wasmtime :: proc(wasm_path: string) -> (stdout: string, stderr: string, exit_code: int) {
	desc := os.Process_Desc{
		command = {"/home/smores/.wasmtime/bin/wasmtime", "run", wasm_path},
	}
	state, stdout_data, stderr_data, err := os.process_exec(desc, context.allocator)
	if err != nil {
		return "", fmt.tprintf("failed to execute wasmtime: {}", err), 1
	}
	defer delete(stdout_data, context.allocator)
	defer delete(stderr_data, context.allocator)

	exit_code = state.exit_code
	stdout = capture_output(stdout_data)
	stderr = capture_output(stderr_data)
	return
}

run_special_command :: proc(args: string, tmp_base: string, camp_filename: string) -> (stdout: string, stderr: string, exit_code: int) {
	switch args {
	case "no-args":
		desc := os.Process_Desc{
			command = {"./camp"},
		}
		state, stdout_data, stderr_data, err := os.process_exec(desc, context.allocator)
		if err != nil {
			return "", fmt.tprintf("failed to execute camp: {}", err), 1
		}
		defer delete(stdout_data, context.allocator)
		defer delete(stderr_data, context.allocator)
		return capture_output(stdout_data), capture_output(stderr_data), state.exit_code

	case "unknown":
		desc := os.Process_Desc{
			command = {"./camp", "foo"},
		}
		state, stdout_data, stderr_data, err := os.process_exec(desc, context.allocator)
		if err != nil {
			return "", fmt.tprintf("failed to execute camp: {}", err), 1
		}
		defer delete(stdout_data, context.allocator)
		defer delete(stderr_data, context.allocator)
		return capture_output(stdout_data), capture_output(stderr_data), state.exit_code

	case "build-non-camp":
		txt_path, tp_err := filepath.join({tmp_base, "test.txt"}, context.allocator)
		if tp_err != nil {
			return "", fmt.tprintf("failed to build path: {}", tp_err), 1
		}
		defer delete(txt_path, context.allocator)
		write_err := os.write_entire_file_from_string(txt_path, "not a camp file")
		if write_err != nil {
			return "", fmt.tprintf("failed to write test file: {}", write_err), 1
		}
		desc := os.Process_Desc{
			command = {"./camp", "build", txt_path},
		}
		state, stdout_data, stderr_data, err := os.process_exec(desc, context.allocator)
		if err != nil {
			return "", fmt.tprintf("failed to execute camp: {}", err), 1
		}
		defer delete(stdout_data, context.allocator)
		defer delete(stderr_data, context.allocator)
		return capture_output(stdout_data), capture_output(stderr_data), state.exit_code

	case "build-missing":
		desc := os.Process_Desc{
			command = {"./camp", "build", "/nonexistent.camp"},
		}
		state, stdout_data, stderr_data, err := os.process_exec(desc, context.allocator)
		if err != nil {
			return "", fmt.tprintf("failed to execute camp: {}", err), 1
		}
		defer delete(stdout_data, context.allocator)
		defer delete(stderr_data, context.allocator)
		return capture_output(stdout_data), capture_output(stderr_data), state.exit_code
	}

	return "", fmt.tprintf("unknown special args: {}", args), 1
}

write_string_diff :: proc(buf: ^strings.Builder, field: string, expected: string, actual: string) {
	if strings.contains(expected, "\n") || strings.contains(actual, "\n") {
		fmt.sbprintf(buf, "  {}:\n", field)
		expected_lines := strings.split(expected, "\n", context.allocator)
		defer delete(expected_lines, context.allocator)
		actual_lines := strings.split(actual, "\n", context.allocator)
		defer delete(actual_lines, context.allocator)

		max_len := len(expected_lines)
		if len(actual_lines) > max_len { max_len = len(actual_lines) }

		for i in 0..<max_len {
			e_line := ""
			a_line := ""
			if i < len(expected_lines) { e_line = expected_lines[i] }
			if i < len(actual_lines) { a_line = actual_lines[i] }
			if e_line != a_line {
				fmt.sbprintf(buf, "    - {}\n", e_line)
				fmt.sbprintf(buf, "    + {}\n", a_line)
			}
		}
	} else {
		fmt.sbprintf(buf, "  {}: expected {:q}, got {:q}\n", field, expected, actual)
	}
}

write_update_file :: proc(path: string, stdout: string, stderr: string, exit: int, has_wasm: bool, wasm_stdout: string, wasm_stderr: string, wasm_exit: int) {
	dict: Toml_Dict
	dict.entries = make([dynamic]Toml_Entry, 0, 8, context.allocator)
	defer delete(dict.entries)

	append(&dict.entries, Toml_Entry{key = "stdout", value = stdout})
	append(&dict.entries, Toml_Entry{key = "stderr", value = stderr})
	append(&dict.entries, Toml_Entry{key = "exit", value = exit})

	if has_wasm {
		append(&dict.entries, Toml_Entry{key = "wasm_exit", value = wasm_exit})
		append(&dict.entries, Toml_Entry{key = "wasm_stdout", value = wasm_stdout})
		append(&dict.entries, Toml_Entry{key = "wasm_stderr", value = wasm_stderr})
	}

	buf: strings.Builder
	strings.builder_init_none(&buf, context.allocator)
	defer strings.builder_destroy(&buf)

	toml_write(&dict, &buf)

	content := strings.to_string(buf)
	_ = os.write_entire_file_from_string(path, content)
}
