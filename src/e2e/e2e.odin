package e2e

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:sync"
import "core:thread"

Test_Worker_Context :: struct {
	tests:    []E2E_Test,
	update:   bool,
	reports:  ^[dynamic]Test_Report,
	mutex:    ^sync.Mutex,
}

run_test_worker :: proc(ctx_ptr: rawptr) {
	ctx := cast(^Test_Worker_Context)ctx_ptr
	for test in ctx.tests {
		test_arena: virtual.Arena
		arena_err := virtual.arena_init_growing(&test_arena)
		if arena_err != nil {
			report := Test_Report{
				test = test,
				result = .Fail,
				diff = fmt.tprintf("  ERROR: failed to init arena: {}", arena_err),
			}
			sync.mutex_lock(ctx.mutex)
			append(ctx.reports, report)
			sync.mutex_unlock(ctx.mutex)
			continue
		}

		old_alloc := context.allocator
		context.allocator = virtual.arena_allocator(&test_arena)

		report := run_test(test, ctx.update)

		context.allocator = old_alloc
		virtual.arena_destroy(&test_arena)

		sync.mutex_lock(ctx.mutex)
		append(ctx.reports, report)
		sync.mutex_unlock(ctx.mutex)
	}
}

main :: proc() {
	args := os.args
	update := false
	verbose := false
	filter := ""

	i: int = 1
	for i < len(args) {
		if args[i] == "--update" {
			update = true
		} else if args[i] == "--verbose" {
			verbose = true
		} else if args[i] == "--filter" && i + 1 < len(args) {
			filter = args[i+1]
			i += 1
		}
		i += 1
	}

	tests := discover_tests("tests/e2e", filter, context.allocator)

	if len(tests) == 0 {
		fmt.println("no e2e tests found")
		os.exit(1)
	}
	defer delete(tests)

	reports: [dynamic]Test_Report
	reports.allocator = context.allocator
	mutex: sync.Mutex

	num_workers := len(tests)
	if num_workers > 8 {
		num_workers = 8
	}
	if num_workers < 1 {
		num_workers = 1
	}

	tests_per_worker := len(tests) / num_workers
	remainder := len(tests) % num_workers

	worker_ctxs := make([]Test_Worker_Context, num_workers)

	offset := 0
	for w in 0..<num_workers {
		count := tests_per_worker
		if w < remainder {
			count += 1
		}
		worker_ctxs[w] = Test_Worker_Context{
			tests = tests[offset:offset + count],
			update = update,
			reports = &reports,
			mutex = &mutex,
		}
		offset += count
	}

	threads := make([]^thread.Thread, num_workers)
	for w in 0..<num_workers {
		threads[w] = thread.create_and_start_with_data(&worker_ctxs[w], run_test_worker)
	}

	for t in threads {
		thread.join(t)
		thread.destroy(t)
	}

	pass_count: int = 0
	fail_count: int = 0
	skip_count: int = 0

	for report in reports {
		switch report.result {
		case .Pass:
			pass_count += 1
			if report.updated {
				fmt.printfln("  UPDATED  {}/{}", report.test.category, report.test.name)
			} else if verbose {
				fmt.printfln("  PASS  {}/{}", report.test.category, report.test.name)
				fmt.printfln("    stdout: {}", report.actual_stdout)
				fmt.printfln("    stderr: {}", report.actual_stderr)
				fmt.printfln("    exit: {}", report.actual_exit)
			}
		case .Fail:
			fail_count += 1
			fmt.printfln("  FAIL  {}/{}", report.test.category, report.test.name)
			if len(report.diff) > 0 {
				fmt.println(report.diff)
			}
		case .Skip:
			skip_count += 1
			fmt.printfln("  SKIP  {}/{}", report.test.category, report.test.name)
		}
	}

	fmt.printfln("\n{} passed, {} failed, {} skipped ({} total)", pass_count, fail_count, skip_count, len(tests))

	if fail_count > 0 {
		os.exit(1)
	}
}
