package diagnostics

import "core:fmt"

explain_for_code :: proc(code: string) -> (string, bool) {
	switch code {
	case "C0001":
		return "An unexpected character was found in the source. Check for invalid Unicode or non-Camp tokens.",
			true
	case "C0002":
		return "A string literal was not properly terminated. Ensure all strings have matching opening and closing quotes.",
			true
	case "C0100":
		return "The name used here is not defined in the current scope. Check for typos or missing imports.",
			true
	case "C0101":
		return "A name is defined more than once in the same scope. Rename or remove the duplicate.",
			true
	case "C0200":
		return "The types in this expression are incompatible. Check the type annotations and inferred types.",
			true
	case "C0202":
		return "The branches of an if expression have mismatched types. Both branches must produce the same type.",
			true
	case "C0300":
		return "This effect is not handled in the enclosing context. Add a handle block or declare it in the effect row.",
			true
	case "C0301":
		return "An effectful function must have a '!' suffix on its name to indicate it may perform effects.",
			true
	case "C0412":
		return "Two or more effects handled in the same `handle` block declare an operation with the same name. The `.op(resume, args)` clause has no effect qualifier, so the compiler cannot tell which effect's operation to bind. Split into separate `handle` blocks or rename the op.",
			true
	}
	return "", false
}

KNOWN_CODES :: [?]string {
	"C0001",
	"C0002",
	"C0100",
	"C0101",
	"C0200",
	"C0202",
	"C0300",
	"C0301",
	"C0412",
	"C0900",
}

run_explain :: proc(code: string) -> bool {
	if explanation, ok := explain_for_code(code); ok {
		fmt.printfln("{}: {}", code, explanation)
		return true
	}
	fmt.printfln("No explanation found for error code '{}'.", code)
	fmt.println("Run 'camp --explain' to list known error codes.")
	return false
}

list_codes :: proc() {
	fmt.println("Known error codes:")
	for code in KNOWN_CODES {
		fmt.printfln("  {}", code)
	}
	fmt.println("\nRun 'camp --explain <code>' for a detailed explanation.")
}

