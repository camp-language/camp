package camp

import "camp:doc"
import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_extract_simple_code_block :: proc(t: ^testing.T) {
	doc_text := "This is a doc comment.\n```\n42 + 1\n```"
	tests := doc.extract_doc_tests(doc_text, "add_one", "/test.camp", 0)
	defer delete(tests)

	testing.expect(t, len(tests) == 1, fmt.tprintf("expected 1 test, got {}", len(tests)))
	testing.expect(t, tests[0].code == "42 + 1", fmt.tprintf("expected code '42 + 1', got '{}'", tests[0].code))
	testing.expect(t, tests[0].decl_name == "add_one")
	testing.expect(t, tests[0].decl_path == "/test.camp")
}

@(test)
test_extract_multiple_code_blocks :: proc(t: ^testing.T) {
	doc_text := "Text.\n```\nfirst\n```\ntext\n```\nsecond\n```"
	tests := doc.extract_doc_tests(doc_text, "multi", "/test.camp", 0)
	defer delete(tests)

	testing.expect(t, len(tests) == 2, fmt.tprintf("expected 2 tests, got {}", len(tests)))
	testing.expect(t, tests[0].code == "first")
	testing.expect(t, tests[1].code == "second")
}

@(test)
test_extract_hidden_lines_removed :: proc(t: ^testing.T) {
	doc_text := "```\nvisible\n//# hidden\nalso_visible\n```"
	tests := doc.extract_doc_tests(doc_text, "hidden_test", "/test.camp", 0)
	defer delete(tests)

	testing.expect(t, len(tests) == 1)
	lines := strings.split(tests[0].code, "\n", context.allocator)
	defer delete(lines, context.allocator)
	testing.expect(t, len(lines) == 2, fmt.tprintf("expected 2 lines, got {}", len(lines)))
	testing.expect(t, lines[0] == "visible")
	testing.expect(t, lines[1] == "also_visible")
}

@(test)
test_extract_block_with_label :: proc(t: ^testing.T) {
	doc_text := "```my_label\nx = 42\n```"
	tests := doc.extract_doc_tests(doc_text, "labeled", "/test.camp", 0)
	defer delete(tests)

	testing.expect(t, len(tests) == 1)
	testing.expect(t, tests[0].name == "my_label")
	testing.expect(t, tests[0].code == "x = 42")
}

@(test)
test_extract_no_code_blocks :: proc(t: ^testing.T) {
	doc_text := "Just regular doc text.\nNo code blocks here."
	tests := doc.extract_doc_tests(doc_text, "no_code_dt", "/test.camp", 0)
	defer delete(tests)

	testing.expect(t, len(tests) == 0)
}

@(test)
test_extract_unclosed_code_block :: proc(t: ^testing.T) {
	doc_text := "```\nunclosed code"
	tests := doc.extract_doc_tests(doc_text, "unclosed_dt", "/test.camp", 0)
	defer delete(tests)

	testing.expect(t, len(tests) == 1, fmt.tprintf("expected 1 test (unclosed block should be captured), got {}", len(tests)))
	testing.expect(t, tests[0].code == "unclosed code")
}

@(test)
test_extract_line_number_offset :: proc(t: ^testing.T) {
	doc_text := "First line\n```\ncode\n```"
	tests := doc.extract_doc_tests(doc_text, "linetest_dt", "/test.camp", 9)
	defer delete(tests)

	testing.expect(t, len(tests) == 1)
	testing.expect(t, tests[0].name == "11", fmt.tprintf("expected name '11', got '{}'", tests[0].name))
}

@(test)
test_join_code_lines :: proc(t: ^testing.T) {
	lines := []string{"a", "b", "c"}
	result := doc.join_code_lines(lines[:])
	testing.expect(t, result == "a\nb\nc", fmt.tprintf("expected 'a\\nb\\nc', got '{}'", result))
}

@(test)
test_join_code_lines_empty :: proc(t: ^testing.T) {
	lines := []string{}
	result := doc.join_code_lines(lines[:])
	testing.expect(t, result == "")
}

@(test)
test_join_code_lines_single :: proc(t: ^testing.T) {
	lines := []string{"single"}
	result := doc.join_code_lines(lines[:])
	testing.expect(t, result == "single")
}
