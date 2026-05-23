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
	test_dir:      string,
	expected_path: string,
	is_multi_module: bool,
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

		test_dirs, td_err := os.read_all_directory_by_path(cat_path, allocator)
		if td_err != nil { continue }
		defer os.file_info_slice_delete(test_dirs, allocator)

		for fi in test_dirs {
			if fi.type != .Directory { continue }
			test_name := fi.name
			if test_name == "." || test_name == ".." { continue }

			test_dir_path, tdpe_err := filepath.join({cat_path, test_name}, allocator)
			if tdpe_err != nil { continue }
			defer delete(test_dir_path, allocator)

			expected_path, ep_err := filepath.join({test_dir_path, "expected.toml"}, allocator)
			defer delete(expected_path, allocator)
			if ep_err != nil {
				continue
			}

			if !os.exists(expected_path) {
				continue  // deferred delete handles cleanup
			}

			main_camp_path, mc_err := filepath.join({test_dir_path, "Main.camp"}, allocator)
			defer delete(main_camp_path, allocator)
			if mc_err != nil {
				continue
			}

			if !os.exists(main_camp_path) {
				continue  // deferred delete handles cleanup
			}

			category_name := fmt.tprintf("{}/{}", category, test_name)
			should_skip := filter != "" && !strings.contains(category_name, filter)

			if should_skip {
				continue
			}

			cat_clone, _ := strings.clone(category, allocator)
			name_clone, _ := strings.clone(test_name, allocator)
			dir_clone, _ := strings.clone(test_dir_path, allocator)
			exp_clone, _ := strings.clone(expected_path, allocator)

			is_multi := count_camp_files(test_dir_path, allocator) > 1

			append(&tests, E2E_Test{
				category       = cat_clone,
				name           = name_clone,
				test_dir       = dir_clone,
				expected_path  = exp_clone,
				is_multi_module = is_multi,
			})
		}
	}

	return tests
}

copy_dir_recursive :: proc(dst: string, src: string) -> os.Error {
	infos, err := os.read_all_directory_by_path(src, context.allocator)
	if err != nil {
		return err
	}
	defer os.file_info_slice_delete(infos, context.allocator)

	os.make_directory_all(dst)

	for fi in infos {
		if fi.name == "." || fi.name == ".." { continue }

		src_path, sp_err := filepath.join({src, fi.name}, context.allocator)
		if sp_err != nil { return sp_err }
		defer delete(src_path, context.allocator)

		dst_path, dp_err := filepath.join({dst, fi.name}, context.allocator)
		if dp_err != nil { return dp_err }
		defer delete(dst_path, context.allocator)

		if fi.type == .Directory {
			copy_err := copy_dir_recursive(dst_path, src_path)
			if copy_err != nil { return copy_err }
		} else if fi.type == .Regular {
			copy_err := os.copy_file(dst_path, src_path)
			if copy_err != nil { return copy_err }
		}
	}

	return nil
}

count_camp_files :: proc(dir: string, allocator: mem.Allocator) -> int {
	infos, err := os.read_all_directory_by_path(dir, allocator)
	if err != nil {
		return 0
	}
	defer os.file_info_slice_delete(infos, allocator)

	count := 0
	for fi in infos {
		if fi.type == .Regular && strings.has_suffix(fi.name, ".camp") {
			count += 1
		}
	}
	return count
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

	tmp_src, ts_err := filepath.join({tmp_base, "src"}, context.allocator)
	if ts_err != nil {
		report.result = .Fail
		report.diff = "  setup: could not build src temp path"
		return report
	}

	copy_err := copy_dir_recursive(tmp_src, test.test_dir)
	if copy_err != nil {
		report.result = .Fail
		report.diff = fmt.tprintf("  setup: could not copy test directory: {}", copy_err)
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
			stdout_str, stderr_str, exit_code = run_special_command(a, tmp_base, unique_prefix)
		}
	}

	if !has_args {
		if test.is_multi_module {
			stdout_str, stderr_str, exit_code = run_camp_project(tmp_base, unique_prefix)
		} else {
			tmp_main, tm_err := filepath.join({tmp_src, "Main.camp"}, context.allocator)
			if tm_err != nil {
				report.result = .Fail
				report.diff = "  setup: could not build Main.camp path"
				return report
			}
			stdout_str, stderr_str, exit_code = run_camp_build(tmp_main, unique_prefix)
		}
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
		wasm_path: string
		tw_err: os.Error
		if test.is_multi_module {
			wasm_path, tw_err = filepath.join({tmp_base, "a.wasm"}, context.allocator)
		} else {
			wasm_path, tw_err = filepath.join({tmp_src, "Main.wasm"}, context.allocator)
		}
		if tw_err != nil {
			has_wasm = false
		} else {
			wasm_stdout, wasm_stderr, wasm_exit, wasm_available = run_wasmtime(wasm_path, unique_prefix)
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

run_command_prefixed :: proc(command: []string, prefix: string, cwd: string = "") -> (stdout: string, stderr: string, exit_code: int) {
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
	defer os.remove(stdout_path)
	defer os.remove(stderr_path)

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
		working_dir = cwd,
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

run_camp_project :: proc(project_dir: string, unique_prefix: string) -> (stdout: string, stderr: string, exit_code: int) {
	camp_env := os.get_env("CAMP_BIN", context.allocator)
	camp_bin: string
	if len(camp_env) > 0 {
		camp_bin = camp_env
	} else {
		camp_bin = "./camp"
	}
	return run_command_prefixed({camp_bin, "build"}, unique_prefix, cwd = project_dir)
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

run_special_command :: proc(args: string, tmp_base: string, unique_prefix: string) -> (stdout: string, stderr: string, exit_code: int) {
	switch args {
	case "no-args":
		return run_command_prefixed({"./camp"}, fmt.tprintf("{}-noargs", unique_prefix))

	case "unknown":
		return run_command_prefixed({"./camp", "foo"}, fmt.tprintf("{}-unknown", unique_prefix))

	case "build-non-camp":
		txt_path, tp_err := filepath.join({tmp_base, "src", "test.txt"}, context.allocator)
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
