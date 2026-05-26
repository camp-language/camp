package diagnostics

import "camp:base"

import "core:fmt"

Diagnostic_Category :: enum {
	Warning,
	Error,
	Internal,
}

Span_Label :: struct {
	span:  base.Source_Span,
	label: string,
}

Diagnostic :: struct {
	category:      Diagnostic_Category,
	code:          string,
	span:          base.Source_Span,
	message:       string,
	title:         string,
	labels:        [dynamic]Span_Label,
	hints:         [dynamic]string,
	shadowed_name: base.Intern_ID,
}

Lex_Unexpected_Char :: struct {
	char: u8,
}
Lex_Unterminated_String :: struct {}

Parse_Expected_Token :: struct {
	expected: base.Token_Kind,
	actual:   base.Token,
}
Parse_Unexpected_Token :: struct {
	token: base.Token,
}
Parse_Expected_Type :: struct {
	actual: base.Token,
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
	span_b: base.Source_Span,
}
Unify_Primitive_Mismatch :: struct {
	name_a: string,
	name_b: string,
	span_b: base.Source_Span,
}
Unify_Value_Row_Conflict :: struct {
	kind_a: string,
	kind_b: string,
	span_b: base.Source_Span,
}
Unify_Infinite_Type :: struct {
	type_expr: string,
	span_b:    base.Source_Span,
}
Unify_Arity_Mismatch :: struct {
	expected: int,
	actual:   int,
	span_b:   base.Source_Span,
}
Unify_Tag_Arity_Mismatch :: struct {
	tag_name: string,
	expected: int,
	actual:   int,
	span_b:   base.Source_Span,
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
	name:        string,
	module_name: string,
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

Trait_Orphan_Rule_Violation :: struct {
	type_name:  string,
	trait_name: string,
}
Trait_Overlapping_Instance :: struct {
	type_name:  string,
	trait_name: string,
}
Trait_Constraint_Violation :: struct {
	type_name:  string,
	constraint: string,
}
Trait_Missing_Method :: struct {
	type_name:  string,
	trait_name: string,
	method:     string,
}
Trait_Method_Signature_Mismatch :: struct {
	type_name:    string,
	trait_name:   string,
	method:       string,
	expected_sig: string,
	actual_sig:   string,
}
Newtype_Opaque_Violation :: struct {
	type_name: string,
	action:    string,
}

Unused_Binding :: struct {
	name: string,
	hint: string,
}

Unused_Record_Field :: struct {
	field_name:  string,
	record_span: base.Source_Span,
}

Unused_Import :: struct {
	name:        string,
	module_name: string,
}

Pointless_Evaluation :: struct {
	kind: string,
}

Contradictory_Prefix :: struct {
	name: string,
}

Noop_Assignment :: struct {
	name: string,
}

Unused_Assignment :: struct {
	name:      string,
	assign_no: int,
	hint:      string,
}

// Lexer
Lex_Invalid_Escape :: struct {
	escape: string,
}
Lex_Unterminated_Per_Line_String :: struct {}
Lex_Invalid_Numeric_Literal :: struct {
	text: string,
	hint: string,
}
Lex_Unterminated_Block_Comment :: struct {}

// Parser
Parse_Duplicate_Field_Literal :: struct {
	field_name: string,
}
Parse_Duplicate_Field_Pattern :: struct {
	field_name: string,
}
Parse_Duplicate_Variant :: struct {
	variant_name: string,
}
Parse_Duplicate_Effect_Row :: struct {
	effect_name: string,
}
Parse_Invalid_Match_Arm :: struct {}
Parse_Missing_Arrow_Fn_Type :: struct {}
Parse_Invalid_Visibility :: struct {}
Parse_Invalid_Effect_Row_Syntax :: struct {}

// Name Resolution
Name_Undefined_Type :: struct {
	type_name:     string,
	similar_names: []string,
}
Name_Undefined_Effect :: struct {
	effect_name:   string,
	similar_names: []string,
}
Name_Private_Access :: struct {
	name:        string,
	module_name: string,
}
Name_Ambiguous_Reference :: struct {
	name:    string,
	scope_a: string,
	scope_b: string,
}
Name_Not_A_Function :: struct {
	name:      string,
	type_name: string,
}
Name_Not_A_Type :: struct {
	name: string,
	kind: string,
}
Name_Raw_Id_Not_Needed :: struct {
	name: string,
}

// Type System
Type_Cannot_Infer_Return :: struct {}
Type_Annotation_Mismatch :: struct {
	annotated:       string,
	inferred:        string,
	annotation_span: base.Source_Span,
}
Type_Missing_Field :: struct {
	type_name:  string,
	field_name: string,
}
Type_Unknown_Field :: struct {
	field_name:    string,
	type_name:     string,
	similar_names: []string,
}
Type_Field_Type_Mismatch :: struct {
	field_name: string,
	expected:   string,
	actual:     string,
}
Type_Cannot_Unify_Effect_Rows :: struct {
	actual_row:   string,
	expected_row: string,
	effect_name:  string,
	effect_span:  base.Source_Span,
}
Type_Row_Label_Mismatch :: struct {
	actual_row:    string,
	expected_row:  string,
	missing_label: string,
	extra_label:   string,
}
Type_Param_Kind_Mismatch :: struct {
	param_name:    string,
	expected_kind: string,
	actual_name:   string,
	actual_kind:   string,
}
Type_Recursive_Alias :: struct {
	alias_name: string,
}
Type_Invalid_Main_Signature :: struct {
	actual_type: string,
}
Type_Duplicate_Type_Param :: struct {
	param_name: string,
}
Type_Empty_Tag_Union :: struct {
	type_name: string,
}

// Effect System
Effect_Row_Mismatch :: struct {
	actual_row:     string,
	expected_row:   string,
	ctx:            string,
	missing_effect: string,
}
Effect_Unnecessary_In_Signature :: struct {
	effect_name: string,
}
Effect_Not_In_Scope :: struct {
	effect_name:   string,
	similar_names: []string,
}
Effect_Handler_Signature_Mismatch :: struct {
	effect_name: string,
	expected:    int,
	actual:      int,
}
Effect_Missing_Resume :: struct {
	effect_name: string,
}
Effect_Double_Resume :: struct {
	effect_name: string,
}
Effect_Invalid_Resume :: struct {}
Effect_Redundant_Handler :: struct {
	effect_name: string,
}
Effect_Row_Subtype :: struct {
	actual_row:   string,
	declared_row: string,
}

// Pattern Matching
Match_Non_Exhaustive_Tag :: struct {
	type_name:       string,
	missing_variant: string,
}
Match_Fragile :: struct {
	type_name: string,
}
Match_Invalid_Irrefutable :: struct {
	pattern: string,
}
Match_Missing_Field_Pattern :: struct {
	field_name: string,
}
Match_Unknown_Field_Pattern :: struct {
	field_name:    string,
	type_name:     string,
	similar_names: []string,
}
Match_Duplicate_Binding :: struct {
	name: string,
}
Match_Wildcard_After_Catch_All :: struct {}

// Traits/Generics
Trait_Missing_Constraint :: struct {
	param_name: string,
	constraint: string,
}
Trait_Conflicting_Implementations :: struct {
	trait_name:  string,
	type_name:   string,
	other_trait: string,
}
Trait_Not_Found :: struct {
	trait_name:    string,
	similar_names: []string,
}
Trait_Supertrait_Not_Satisfied :: struct {
	trait_name: string,
	supertrait: string,
	type_name:  string,
}
Trait_Cyclic_Dependency :: struct {
	trait_name: string,
	cycle:      string,
}
Trait_Ambiguous_Resolution :: struct {
	trait_name: string,
	type_name:  string,
}

// Newtype
Newtype_Field_Access :: struct {
	field_name: string,
	type_name:  string,
}

// Module/Import
Import_Duplicate :: struct {
	name:        string,
	module_name: string,
}
Import_Shadows_Binding :: struct {
	name: string,
}
Import_Self :: struct {
	module_name: string,
}
Import_Suggest :: struct {
	type_name:   string,
	module_name: string,
}

// Unused Analysis
Unused_Function :: struct {
	name: string,
}
Unused_Type_Definition :: struct {
	type_name: string,
}
Unused_Type_Parameter :: struct {
	param_name: string,
}
Unused_Effect_Handler :: struct {
	effect_name: string,
}
Unreachable_Code :: struct {}
Must_Use_Discarded :: struct {
	function_name: string,
}
Redundant_Else :: struct {}
Unnecessary_Mutability :: struct {
	name: string,
}

// Perceus/RC
RC_Reference_Leak :: struct {
	type_name: string,
}
RC_Unnecessary_Copy :: struct {}
RC_Consume_After_Use :: struct {
	name:         string,
	consume_span: base.Source_Span,
}

// CLI/Build
CLI_Output_Dir_Not_Found :: struct {
	path: string,
}
CLI_Invalid_Option :: struct {
	option: string,
}
CLI_Conflicting_Options :: struct {
	option_a: string,
	option_b: string,
}
CLI_Compilation_Limit :: struct {
	limit: string,
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
	case .Warning:
		collector.warning_count += 1
	case .Error:
		collector.error_count += 1
	case .Internal:
		collector.internal_count += 1
	}
}

diag_collector_has_errors :: proc(collector: ^Diagnostic_Collector) -> bool {
	return collector.error_count > 0 || collector.internal_count > 0
}

