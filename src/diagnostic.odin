package camp

import "core:fmt"

Diagnostic_Category :: enum {
	Warning,
	Error,
	Internal,
}

Span_Label :: struct {
	span:  Source_Span,
	label: string,
}

Diagnostic :: struct {
	category: Diagnostic_Category,
	span:     Source_Span,
	message:  string,
	title:    string,
	labels:   [dynamic]Span_Label,
	hints:    [dynamic]string,
}

Lex_Unexpected_Char :: struct {
	char: u8,
}
Lex_Unterminated_String :: struct {}

Parse_Expected_Token :: struct {
	expected: Token_Kind,
	actual:   Token,
}
Parse_Unexpected_Token :: struct {
	token: Token,
}
Parse_Expected_Type :: struct {
	actual: Token,
}

Type_Effectful_Naming :: struct {
	name:    string,
	effects: string,
}
Type_Undefined_Name :: struct {
	name:          string,
	similar_names: []string,
}
Type_Unhandled_Effect :: struct {
	effect_name: string,
}

Unify_Type_Mismatch :: struct {
	type_a: string,
	type_b: string,
	span_b: Source_Span,
}
Unify_Primitive_Mismatch :: struct {
	name_a: string,
	name_b: string,
	span_b: Source_Span,
}
Unify_Value_Row_Conflict :: struct {
	kind_a: string,
	kind_b: string,
	span_b: Source_Span,
}
Unify_Infinite_Type :: struct {
	type_expr: string,
	span_b:    Source_Span,
}
Unify_Arity_Mismatch :: struct {
	expected: int,
	actual:   int,
	span_b:   Source_Span,
}
Unify_Tag_Arity_Mismatch :: struct {
	tag_name: string,
	expected: int,
	actual:   int,
	span_b:   Source_Span,
}

CLI_Invalid_Extension :: struct {
	path:      string,
	extension: string,
}
CLI_File_Not_Found :: struct {
	path:     string,
	os_error: string,
}
CLI_Unknown_Command :: struct {
	command: string,
}

Module_Not_Found :: struct {
	module_name: string,
}
Module_Cyclic_Dep :: struct {
	cycle_path: string,
}
Import_Not_Exported :: struct {
	name:         string,
	module_name:  string,
}
Import_Conflicts_Binding :: struct {
	name:        string,
	module_name: string,
}
Import_Ambiguous :: struct {
	name:  string,
	mod_a: string,
	mod_b: string,
}
Entry_Point_Not_Found :: struct {}
Entry_Point_No_Main :: struct {}
Project_No_Source :: struct {}
Module_Duplicate_Name :: struct {
	name: string,
}

Diagnostic_Collector :: struct {
	diagnostics:    [dynamic]Diagnostic,
	warning_count:  int,
	error_count:    int,
	internal_count: int,
}

diag_collector_init :: proc(collector: ^Diagnostic_Collector) {
	collector.diagnostics = make([dynamic]Diagnostic, 0, 64)
	collector.warning_count = 0
	collector.error_count = 0
	collector.internal_count = 0
}

diag_collector_destroy :: proc(collector: ^Diagnostic_Collector) {
	for &d in collector.diagnostics {
		delete(d.labels)
		delete(d.hints)
	}
	delete(collector.diagnostics)
}

collector_add_diag :: proc(collector: ^Diagnostic_Collector, d: Diagnostic) {
	append(&collector.diagnostics, d)
	switch d.category {
	case .Warning:  collector.warning_count += 1
	case .Error:    collector.error_count += 1
	case .Internal: collector.internal_count += 1
	}
}

diag_collector_has_errors :: proc(collector: ^Diagnostic_Collector) -> bool {
	return collector.error_count > 0 || collector.internal_count > 0
}
