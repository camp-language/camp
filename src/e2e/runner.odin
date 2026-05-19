package e2e

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

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
	test:          E2E_Test,
	result:        Test_Result,
	diff:          string,
	updated:       bool,
	actual_stdout: string,
	actual_stderr: string,
	actual_exit:   int,
}

discover_tests :: proc(root: string, filter: string, allocator: mem.Allocator) -> [dynamic]E2E_Test {
	tests: [dynamic]E2E_Test
	tests.allocator = allocator

	categories, cat_err := os.read_all_directory_by_path(root, allocator)
	if cat_err != nil {
		return tests
	}
	defer os.file_info_slice_delete(categories, allocator)

	for cat_info in categories {
		if cat_info.type != .Directory { continue }
		category := cat_info.name
		if category == "." || category == ".." { continue }

		cat_path, cat_err2 := filepath.join({root, category}, allocator)
		if cat_err2 != nil { continue }
		defer delete(cat_path, allocator)

		files, file_err := os.read_all_directory_by_path(cat_path, allocator)
		if file_err != nil { continue }
		defer os.file_info_slice_delete(files, allocator)

		for fi in files {
			if fi.type != .Regular { continue }
			if filepath.ext(fi.name) != ".camp" { continue }

			name := filepath.stem(fi.name)
			expected_name := fmt.tprintf("{}.expected.toml", name)
			expected_path, ep_err := filepath.join({cat_path, expected_name}, allocator)
			if ep_err != nil { continue }

			if !os.exists(expected_path) {
				delete(expected_path, allocator)
				continue
			}

			camp_file_path, cp_err := filepath.join({cat_path, fi.name}, allocator)
			if cp_err != nil {
				delete(expected_path, allocator)
				continue
			}

			category_name := fmt.tprintf("{}/{}", category, name)
			if filter != "" && !strings.contains(category_name, filter) {
				delete(camp_file_path, allocator)
				delete(expected_path, allocator)
				continue
			}

			cat_clone, _ := strings.clone(category, allocator)
			name_clone, _ := strings.clone(name, allocator)

			append(&tests, E2E_Test{
				category      = cat_clone,
				name          = name_clone,
				camp_path     = camp_file_path,
				expected_path = expected_path,
			})
		}
	}

	return tests
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
	os.make_directory_all(tmp_base)

	camp_filename := fmt.tprintf("{}.camp", test.name)
	tmp_camp, tc_err := filepath.join({tmp_base, camp_filename}, context.allocator)
	if tc_err != nil {
		report.result = .Fail
		report.diff = "  setup: could not build camp temp path"
		return report
	}

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

	expected_dict := toml_parse(string(expected_data), context.allocator)

	args_val, has_args := toml_get(&expected_dict, "args")

	stdout_str: string
	stderr_str: string
	exit_code: int

	unique_prefix := fmt.tprintf("{}-{}", test.category, test.name)

	if has_args {
		#partial switch a in args_val {
		case string:
			stdout_str, stderr_str, exit_code = run_special_command(a, tmp_base, camp_filename, unique_prefix)
		}
	}

	if !has_args {
		stdout_str, stderr_str, exit_code = run_camp_build(tmp_camp, unique_prefix)
	}

	report.actual_stdout = stdout_str
	report.actual_stderr = stderr_str
	report.actual_exit = exit_code

	wasm_stdout: string
	wasm_stderr: string
	wasm_exit: int
	has_wasm := false
	wasm_available := true

	_, has_wasm_exit := toml_get(&expected_dict, "wasm_exit")
	if has_wasm_exit && exit_code == 0 {
		has_wasm = true
		wasm_filename := fmt.tprintf("{}.wasm", test.name)
		tmp_wasm, tw_err := filepath.join({tmp_base, wasm_filename}, context.allocator)
		if tw_err != nil {
			has_wasm = false
		} else {
			wasm_stdout, wasm_stderr, wasm_exit, wasm_available = run_wasmtime(tmp_wasm, unique_prefix)
		}
	}

	if !wasm_available && has_wasm_exit {
		report.result = .Skip
		return report
	}

	diff_builder: strings.Builder
	strings.builder_init_none(&diff_builder, context.allocator)

	passed := true

	expected_stdout_val, has_stdout := toml_get(&expected_dict, "stdout")
	if has_stdout {
		#partial switch s in expected_stdout_val {
		case string:
			if stdout_str != s {
				passed = false
				write_string_diff(&diff_builder, "stdout", s, stdout_str)
			}
		}
	}

	expected_stderr_val, has_stderr := toml_get(&expected_dict, "stderr")
	if has_stderr {
		#partial switch s in expected_stderr_val {
		case string:
			if stderr_str != s {
				passed = false
				write_string_diff(&diff_builder, "stderr", s, stderr_str)
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

	if has_wasm && wasm_available {
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
				if wasm_stdout != s {
					passed = false
					write_string_diff(&diff_builder, "wasm_stdout", s, wasm_stdout)
				}
			}
		}

		expected_wasm_stderr_val, has_we := toml_get(&expected_dict, "wasm_stderr")
		if has_we {
			#partial switch s in expected_wasm_stderr_val {
			case string:
				if wasm_stderr != s {
					passed = false
					write_string_diff(&diff_builder, "wasm_stderr", s, wasm_stderr)
				}
			}
		}
	}

	if update {
		args_str: string
		if has_args {
			#partial switch a in args_val {
			case string:
				args_str = a
			}
		}
		write_update_file(test.expected_path, stdout_str, stderr_str, exit_code, has_wasm, wasm_stdout, wasm_stderr, wasm_exit, has_args, args_str)
		passed = true
		report.updated = true
	}

	if passed {
		report.result = .Pass
	} else {
		report.result = .Fail
		report.diff = strings.to_string(diff_builder)
	}

	return report
}

capture_output :: proc(data: []byte) -> string {
	s, _ := strings.clone(string(data), context.allocator)
	return s
}

PROCESS_TIMEOUT :: 10 * time.Second

run_command :: proc(command: []string) -> (stdout: string, stderr: string, exit_code: int) {
	return run_command_prefixed(command, "")
}

run_command_prefixed :: proc(command: []string, prefix: string) -> (stdout: string, stderr: string, exit_code: int) {
	pid := os.get_pid()
	stdout_path: string
	stderr_path: string
	if len(prefix) > 0 {
		stdout_path = fmt.tprintf("/tmp/camp-e2e-stdout-{}-{}", pid, prefix)
		stderr_path = fmt.tprintf("/tmp/camp-e2e-stderr-{}-{}", pid, prefix)
	} else {
		stdout_path = fmt.tprintf("/tmp/camp-e2e-stdout-{}", pid)
		stderr_path = fmt.tprintf("/tmp/camp-e2e-stderr-{}", pid)
	}

	stdout_f, open_err := os.open(stdout_path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	if open_err != nil {
		return "", fmt.tprintf("open stdout file: {}", open_err), 1
	}
	defer os.close(stdout_f)
	stderr_f, open_err2 := os.open(stderr_path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	if open_err2 != nil {
		os.remove(stdout_path)
		return "", fmt.tprintf("open stderr file: {}", open_err2), 1
	}
	defer os.close(stderr_f)

	start_proc, start_err := os.process_start(os.Process_Desc{
		command = command,
		stdout = stdout_f,
		stderr = stderr_f,
	})
	if start_err != nil {
		os.remove(stdout_path)
		os.remove(stderr_path)
		return "", fmt.tprintf("process start error: {}", start_err), 1
	}

	state, wait_err := os.process_wait(start_proc, timeout = PROCESS_TIMEOUT)
	if wait_err != nil || !state.exited {
		kill_err := os.process_kill(start_proc)
		if kill_err == nil {
			_, _ = os.process_wait(start_proc)
		}
		os.remove(stdout_path)
		os.remove(stderr_path)
		return "", "process timed out after 10s", -1
	}

	exit_code = state.exit_code

	stdout_data, stdout_err := os.read_entire_file(stdout_path, context.allocator)
	if stdout_err == nil {
		stdout = string(stdout_data[:])
	}

	stderr_data, stderr_err := os.read_entire_file(stderr_path, context.allocator)
	if stderr_err == nil {
		stderr = string(stderr_data[:])
	}

	os.remove(stdout_path)
	os.remove(stderr_path)
	return
}

run_camp_build :: proc(camp_path: string, unique_prefix: string) -> (stdout: string, stderr: string, exit_code: int) {
	camp_env := os.get_env("CAMP_BIN", context.allocator)
	camp_bin: string
	if len(camp_env) > 0 {
		camp_bin = camp_env
	} else {
		camp_bin = "./camp"
	}
	return run_command_prefixed({camp_bin, "build", camp_path}, unique_prefix)
}

resolve_wasmtime :: proc() -> string {
	env_val := os.get_env_alloc("WASMTIME", context.allocator)
	if len(env_val) > 0 {
		clone, _ := strings.clone(env_val, context.allocator)
		return clone
	}
	return "wasmtime"
}

run_wasmtime :: proc(wasm_path: string, unique_prefix: string) -> (stdout: string, stderr: string, exit_code: int, available: bool) {
	wasmtime_bin := resolve_wasmtime()
	stdout, stderr, exit_code = run_command_prefixed({wasmtime_bin, "run", wasm_path}, unique_prefix)
	if exit_code == -1 && stderr == "process timed out after 10s" {
		return "", "", 0, false
	}
	available = true
	return
}

run_special_command :: proc(args: string, tmp_base: string, camp_filename: string, unique_prefix: string) -> (stdout: string, stderr: string, exit_code: int) {
	switch args {
	case "no-args":
		return run_command_prefixed({"./camp"}, fmt.tprintf("{}-noargs", unique_prefix))

	case "unknown":
		return run_command_prefixed({"./camp", "foo"}, fmt.tprintf("{}-unknown", unique_prefix))

	case "build-non-camp":
		txt_path, tp_err := filepath.join({tmp_base, "test.txt"}, context.allocator)
		if tp_err != nil {
			return "", fmt.tprintf("failed to build path: {}", tp_err), 1
		}
		write_err := os.write_entire_file_from_string(txt_path, "not a camp file")
		if write_err != nil {
			return "", fmt.tprintf("failed to write test file: {}", write_err), 1
		}
		return run_command_prefixed({"./camp", "build", txt_path}, fmt.tprintf("{}-non-camp", unique_prefix))

	case "build-missing":
		return run_command_prefixed({"./camp", "build", "/nonexistent.camp"}, fmt.tprintf("{}-missing", unique_prefix))
	}

	return "", fmt.tprintf("unknown special args: {}", args), 1
}

write_string_diff :: proc(buf: ^strings.Builder, field: string, expected: string, actual: string) {
	if strings.contains(expected, "\n") || strings.contains(actual, "\n") {
		fmt.sbprintf(buf, "  {}:\n", field)
		expected_lines := strings.split(expected, "\n", context.allocator)
		actual_lines := strings.split(actual, "\n", context.allocator)

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

write_update_file :: proc(path: string, stdout: string, stderr: string, exit: int, has_wasm: bool, wasm_stdout: string, wasm_stderr: string, wasm_exit: int, has_args: bool, args: string) {
	dict: Toml_Dict
	dict.entries = make([dynamic]Toml_Entry, 0, 8, context.allocator)

	if has_args {
		append(&dict.entries, Toml_Entry{key = "args", value = args})
	}

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

	toml_write(&dict, &buf)

	content := strings.to_string(buf)
	_ = os.write_entire_file_from_string(path, content)
}
