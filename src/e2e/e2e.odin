package e2e

import "core:fmt"
import "core:os"

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

	tests := discover_tests("tests/e2e", filter)

	if len(tests) == 0 {
		fmt.println("no e2e tests found")
		os.exit(1)
	}

	pass_count: int = 0
	fail_count: int = 0
	skip_count: int = 0

	for test in tests {
		report := run_test(test, update)

		switch report.result {
		case .Pass:
			pass_count += 1
			if report.updated {
				fmt.printfln("  UPDATED  {}/{}", test.category, test.name)
			} else if verbose {
				fmt.printfln("  PASS  {}/{}", test.category, test.name)
				fmt.printfln("    stdout: {}", report.actual_stdout)
				fmt.printfln("    stderr: {}", report.actual_stderr)
				fmt.printfln("    exit: {}", report.actual_exit)
			}
		case .Fail:
			fail_count += 1
			fmt.printfln("  FAIL  {}/{}", test.category, test.name)
			if len(report.diff) > 0 {
				fmt.println(report.diff)
			}
		case .Skip:
			skip_count += 1
			fmt.printfln("  SKIP  {}/{}", test.category, test.name)
		}
	}

	fmt.printfln("\n{} passed, {} failed, {} skipped ({} total)", pass_count, fail_count, skip_count, len(tests))

	if fail_count > 0 {
		os.exit(1)
	}
}
