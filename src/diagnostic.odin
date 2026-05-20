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

// Diagnostic_Origin: was this error caused by something in this decl directly,
// or did it cascade from a prior broken decl? The renderer collapses Cascades
// so error storms from one bad decl don't drown out the root cause.
Diagnostic_Origin :: union {
	Origin_Root,
	Origin_Cascade,
}
Origin_Root :: struct {}
Origin_Cascade :: struct {
	// Name of the broken decl this cascade depends on; renderer groups by this.
	root: Intern_ID,
}

Diagnostic :: struct {
	category:     Diagnostic_Category,
	span:         Source_Span,
	message:      string,
	title:        string,
	labels:       [dynamic]Span_Label,
	hints:        [dynamic]string,
	origin:       Diagnostic_Origin,
	// Which decl produced this diagnostic. NO_NAME if not produced inside a decl
	// (lex/parse errors, CLI errors, etc.). Populated when diagnostics are
	// flushed at end of typecheck_decl.
	owning_decl:  Intern_ID,
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
	d := d
	if d.owning_decl == 0 && d.origin == nil {
		// Default for diagnostics that bypass the per-decl pen
		// (lex/parse/CLI). NO_NAME is -1; the zero value 0 means "unset".
		d.owning_decl = NO_NAME
		d.origin = Origin_Root{}
	}
	append(&collector.diagnostics, d)
	switch d.category {
	case .Warning:  collector.warning_count += 1
	case .Error:    collector.error_count += 1
	case .Internal: collector.internal_count += 1
	}
}

// During typecheck of a decl, diagnostics route through this so they pick up
// the owning_decl tag and inherit the cascade status of the surrounding decl.
typecheck_emit :: proc(store: ^Type_Store, d: Diagnostic) {
	if store.current_decl == NO_NAME {
		// Outside a decl context (shouldn't happen in well-formed typecheck,
		// but doesn't break correctness). Pass through.
		collector_add_diag(store.collector, d)
		return
	}
	d := d
	append(&store.pen, d)
}

// Called at end of typecheck_decl. Decides root-vs-cascade for the whole
// batch, marks the decl broken if any errors landed, and flushes to collector.
typecheck_flush_decl :: proc(store: ^Type_Store) {
	had_errors := false
	for d in store.pen {
		if d.category == .Error || d.category == .Internal {
			had_errors = true
			break
		}
	}
	if had_errors {
		store.broken_decls[store.current_decl] = true
	}

	cascade_root := store.current_decl_depends_on_broken

	for d in store.pen {
		flushed := d
		flushed.owning_decl = store.current_decl
		if cascade_root != NO_NAME {
			flushed.origin = Origin_Cascade{root = cascade_root}
		} else {
			flushed.origin = Origin_Root{}
		}
		append(&store.collector.diagnostics, flushed)
		switch flushed.category {
		case .Warning:  store.collector.warning_count += 1
		case .Error:    store.collector.error_count += 1
		case .Internal: store.collector.internal_count += 1
		}
	}
	clear(&store.pen)
}

diag_collector_has_errors :: proc(collector: ^Diagnostic_Collector) -> bool {
	return collector.error_count > 0 || collector.internal_count > 0
}
