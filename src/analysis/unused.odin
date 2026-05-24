package analysis

import "core:fmt"
import "core:strings"
import "camp:base"
import "camp:semantics"
import "camp:diagnostics"

Name_Classification :: enum {
	Normal,
	Underscore,
	Wildcard,
	Contradictory,
	Reassignable,
}

classify_name :: proc(name: base.Intern_ID, interner: ^base.Intern_Table) -> Name_Classification {
	str := base.intern_get(interner, name)
	if len(str) == 0 do return .Normal
	if str == "_" do return .Wildcard
	if strings.has_prefix(str, "_$") || strings.has_prefix(str, "$_") do return .Contradictory
	if strings.has_prefix(str, "$") do return .Reassignable
	if strings.has_prefix(str, "_") do return .Underscore
	return .Normal
}

// Use-site categories for tracking how a binding is consumed
Use_Kind :: enum {
	Read,
	Field_Access,
	Escape_Fn_Arg,
	Escape_Return,
	Escape_Perform,
	Self_Assign_Rhs,
	Discard,
}

Use_Site :: struct {
	kind: Use_Kind,
	span: base.Source_Span,
}

Assignment_Info :: struct {
	span:       base.Source_Span,
	value_expr: semantics.CExpr,
	is_in_loop: bool,
}

Binding_Info :: struct {
	name:                   base.Intern_ID,
	span:                   base.Source_Span,
	classification:         Name_Classification,
	is_top_level:           bool,
	is_pub:                 bool,
	is_effectful:           bool,
	assignments:            [dynamic]Assignment_Info,
	use_sites:              [dynamic]Use_Site,
	field_accesses:         map[base.Intern_ID][dynamic]base.Source_Span,
	escaped:                bool,
}

Import_Info :: struct {
	name:        base.Intern_ID,
	module_name: base.Intern_ID,
	span:        base.Source_Span,
	used:        bool,
}

Record_Field_Info :: struct {
	binding_name: base.Intern_ID,
	field_name:   base.Intern_ID,
	record_span:  base.Source_Span,
	field_span:   base.Source_Span,
	accessed:     bool,
}

Unused_Analysis :: struct {
	bindings:       map[base.Intern_ID]Binding_Info,
	imports:        [dynamic]Import_Info,
	record_fields:  [dynamic]Record_Field_Info,
	shadowed_names: map[base.Intern_ID]bool,
	interner:       ^base.Intern_Table,
	collector:      ^diagnostics.Diagnostic_Collector,
	in_loop:        bool,
	in_unreachable: bool,
}

unused_analysis_init :: proc(analysis: ^Unused_Analysis, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) {
	analysis.bindings = make(map[base.Intern_ID]Binding_Info, 64)
	analysis.imports = make([dynamic]Import_Info, 0, 16)
	analysis.record_fields = make([dynamic]Record_Field_Info, 0, 16)
	analysis.shadowed_names = make(map[base.Intern_ID]bool, 16)
	analysis.interner = interner
	analysis.collector = collector
	analysis.in_loop = false
	analysis.in_unreachable = false
}

unused_analysis_destroy :: proc(analysis: ^Unused_Analysis) {
	for _, &bi in analysis.bindings {
		delete(bi.assignments)
		delete(bi.use_sites)
		for _, spans in bi.field_accesses {
			delete(spans)
		}
		delete(bi.field_accesses)
	}
	delete(analysis.bindings)
	delete(analysis.imports)
	delete(analysis.record_fields)
	delete(analysis.shadowed_names)
}

// Register a binding in the analysis
register_binding :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, span: base.Source_Span, is_top_level: bool, is_pub: bool, is_effectful: bool = false) {
	name_str := base.intern_get(analysis.interner, name)

	bi: Binding_Info
	bi.name = name
	bi.span = span
	bi.classification = classify_name(name, analysis.interner)
	bi.is_top_level = is_top_level
	bi.is_pub = is_pub
	bi.is_effectful = is_effectful
	bi.assignments = make([dynamic]Assignment_Info, 0, 4)
	bi.use_sites = make([dynamic]Use_Site, 0, 8)
	bi.field_accesses = make(map[base.Intern_ID][dynamic]base.Source_Span, 4)
	bi.escaped = false

	analysis.bindings[name] = bi

	if bi.classification == .Contradictory {
		diagnostics.collector_add_diag(analysis.collector,
			diagnostics.diag_contradictory_prefix(name_str, span))
	}
}

// Record a use of a binding
record_use :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, kind: Use_Kind, span: base.Source_Span) {
	if bi, ok := analysis.bindings[name]; ok {
		append(&bi.use_sites, Use_Site{kind = kind, span = span})
		analysis.bindings[name] = bi
	}
}

// Record an assignment to a $-var
record_assignment :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, span: base.Source_Span, value_expr: semantics.CExpr) {
	if bi, ok := analysis.bindings[name]; ok {
		append(&bi.assignments, Assignment_Info{
			span = span,
			value_expr = value_expr,
			is_in_loop = analysis.in_loop,
		})
		analysis.bindings[name] = bi
	}
}

// Mark a binding as escaped (record passed to fn, returned, or used in perform)
mark_escaped :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID) {
	if bi, ok := analysis.bindings[name]; ok {
		bi.escaped = true
		analysis.bindings[name] = bi
	}
}

// Register an import for tracking
register_import :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, module_name: base.Intern_ID, span: base.Source_Span) {
	ii: Import_Info
	ii.name = name
	ii.module_name = module_name
	ii.span = span
	ii.used = false
	append(&analysis.imports, ii)
}

// Mark an import as used
mark_import_used :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID) {
	for &ii in analysis.imports {
		if ii.name == name {
			ii.used = true
			return
		}
	}
}

// Register a record field for tracking
register_record_field :: proc(analysis: ^Unused_Analysis, binding_name: base.Intern_ID, field_name: base.Intern_ID, record_span: base.Source_Span, field_span: base.Source_Span) {
	rfi: Record_Field_Info
	rfi.binding_name = binding_name
	rfi.field_name = field_name
	rfi.record_span = record_span
	rfi.field_span = field_span
	rfi.accessed = false
	append(&analysis.record_fields, rfi)
}

// Mark a record field as accessed
mark_field_accessed :: proc(analysis: ^Unused_Analysis, binding_name: base.Intern_ID, field_name: base.Intern_ID) {
	for &rfi in analysis.record_fields {
		if rfi.binding_name == binding_name && rfi.field_name == field_name {
			rfi.accessed = true
			return
		}
	}
}

// ============================================================
// Phase 1: Use Collection - walk the canonical AST
// ============================================================

collect_uses_cfile :: proc(analysis: ^Unused_Analysis, cfile: semantics.CFile) {
	for decl in cfile.decls {
		collect_uses_decl(analysis, decl)
	}
	for &di in cfile.imports {
		if di.alias != base.NO_NAME {
			register_import(analysis, di.alias, di.module, di.span)
		}
		for name in di.exposing {
			register_import(analysis, name, di.module, di.span)
		}
	}
}

collect_uses_decl :: proc(analysis: ^Unused_Analysis, decl: semantics.CDecl) {
	#partial switch d in decl {
	case ^semantics.CDecl_Const:
		register_binding(analysis, d.name.name, d.span, is_top_level = true, is_pub = d.is_pub, is_effectful = d.is_effectful)
		collect_uses_expr(analysis, d.body)
	case ^semantics.CDecl_Test:
		collect_uses_expr(analysis, d.body)
	case ^semantics.CDecl_Expect:
		collect_uses_expr(analysis, d.condition)
	case ^semantics.CDecl_Effect, ^semantics.CDecl_Trait, ^semantics.CDecl_Alias, ^semantics.CDecl_Newtype, ^semantics.CDecl_Import:
	}
}

collect_uses_expr :: proc(analysis: ^Unused_Analysis, expr: semantics.CExpr) {
	if analysis.in_unreachable do return

	#partial switch e in expr {
	case ^semantics.CExpr_Int:
		{}
	case ^semantics.CExpr_Float:
		{}
	case ^semantics.CExpr_String:
		{}
	case ^semantics.CExpr_Bool:
		{}
	case ^semantics.CExpr_Tag:
		for &payload in e.payload {
			collect_uses_expr(analysis, payload)
		}
	case ^semantics.CExpr_Record:
		for &field in e.fields {
			collect_uses_expr(analysis, field.value)
		}
		if e.rest != nil {
			collect_uses_expr(analysis, e.rest)
		}
	case ^semantics.CExpr_List:
		for &elem in e.elements {
			collect_uses_expr(analysis, elem)
		}
	case ^semantics.CExpr_Name:
		name := e.name.name
		if classify_name(name, analysis.interner) == .Wildcard do return
		record_use(analysis, name, .Read, e.span)
		mark_import_used(analysis, name)
	case ^semantics.CExpr_Call:
		collect_uses_expr(analysis, e.callee)
		for &arg in e.args {
			collect_uses_expr(analysis, arg)
			mark_args_escaped(analysis, arg)
		}
	case ^semantics.CExpr_Method_Call:
		collect_uses_expr(analysis, e.receiver)
		mark_args_escaped(analysis, e.receiver)
		for &arg in e.args {
			collect_uses_expr(analysis, arg)
			mark_args_escaped(analysis, arg)
		}
	case ^semantics.CExpr_Lambda:
		for &param in e.params {
			register_binding(analysis, param.name, param.span, is_top_level = false, is_pub = false)
		}
		collect_uses_expr(analysis, e.body)
	case ^semantics.CExpr_Block:
		for i in 0..<len(e.statements) {
			collect_uses_stmt(analysis, e.statements[i])
		}
	case ^semantics.CExpr_If:
		collect_uses_expr(analysis, e.condition)
		collect_uses_expr(analysis, e.then_branch)
		if e.else_branch != nil {
			collect_uses_expr(analysis, e.else_branch)
		}
	case ^semantics.CExpr_Match:
		collect_uses_expr(analysis, e.scrutinee)
		for &arm in e.arms {
			collect_uses_pattern(analysis, arm.pattern)
			collect_uses_expr(analysis, arm.body)
		}
	case ^semantics.CExpr_BinOp:
		collect_uses_expr(analysis, e.left)
		collect_uses_expr(analysis, e.right)
	case ^semantics.CExpr_PrefixOp:
		collect_uses_expr(analysis, e.operand)
	case ^semantics.CExpr_Field_Access:
		collect_uses_expr(analysis, e.record)
		record_field_access(analysis, e.record, e.field, e.span)
	case ^semantics.CExpr_Record_Update:
		collect_uses_expr(analysis, e.rest)
		for &field in e.updates {
			collect_uses_expr(analysis, field.value)
		}
	case ^semantics.CExpr_Assign:
		collect_uses_assign(analysis, e)
	case ^semantics.CExpr_Return:
		collect_uses_expr(analysis, e.value)
		mark_returned_bindings(analysis, e.value)
	case ^semantics.CExpr_Crash:
		collect_uses_expr(analysis, e.message)
	case ^semantics.CExpr_Interpolated_String:
		for &part in e.parts {
			#partial switch p in part {
			case ^semantics.CExpr_String_Literal:
				{}
			case semantics.CExpr:
				collect_uses_expr(analysis, p)
			}
		}
	case ^semantics.CExpr_Handle:
		collect_uses_expr(analysis, e.body)
		for &arm in e.arms {
			for &param in arm.params {
				register_binding(analysis, param, arm.span, is_top_level = false, is_pub = false)
			}
			collect_uses_expr(analysis, arm.body)
		}
	case ^semantics.CExpr_Perform:
		for &arg in e.args {
			collect_uses_expr(analysis, arg)
			mark_perform_args_escaped(analysis, arg)
		}
	case ^semantics.CExpr_For:
		register_binding(analysis, e.var, e.span, is_top_level = false, is_pub = false)
		old_in_loop := analysis.in_loop
		analysis.in_loop = true
		collect_uses_expr(analysis, e.iterable)
		collect_uses_expr(analysis, e.body)
		analysis.in_loop = old_in_loop
	case ^semantics.CExpr_Par:
		if e.for_var != base.NO_NAME {
			register_binding(analysis, e.for_var, e.span, is_top_level = false, is_pub = false)
		}
		for &expr in e.expressions {
			collect_uses_expr(analysis, expr)
		}
		if e.for_iter != nil {
			collect_uses_expr(analysis, e.for_iter)
		}
		if e.for_body != nil {
			collect_uses_expr(analysis, e.for_body)
		}
	}
}

// Process a statement within a block (handles binding definitions and assignments)
collect_uses_stmt :: proc(analysis: ^Unused_Analysis, stmt: semantics.CExpr) {
	#partial switch s in stmt {
	case ^semantics.CExpr_Name:
		if classify_name(s.name.name, analysis.interner) == .Wildcard do return
		register_binding(analysis, s.name.name, s.span, is_top_level = false, is_pub = false)
	case ^semantics.CExpr_Call:
		collect_uses_expr(analysis, stmt)
	case ^semantics.CExpr_Assign:
		collect_uses_assign(analysis, s)
	case ^semantics.CExpr_Return:
		collect_uses_expr(analysis, s.value)
		mark_returned_bindings(analysis, s.value)
		analysis.in_unreachable = true
	case ^semantics.CExpr_Crash:
		collect_uses_expr(analysis, s.message)
		analysis.in_unreachable = true
	case ^semantics.CExpr_Int, ^semantics.CExpr_Float, ^semantics.CExpr_String, ^semantics.CExpr_Bool,
	     ^semantics.CExpr_Tag, ^semantics.CExpr_Nominal_Construct, ^semantics.CExpr_Record, ^semantics.CExpr_List,
	     ^semantics.CExpr_Method_Call, ^semantics.CExpr_Lambda, ^semantics.CExpr_Block, ^semantics.CExpr_If,
	     ^semantics.CExpr_Match, ^semantics.CExpr_BinOp, ^semantics.CExpr_PrefixOp, ^semantics.CExpr_Field_Access,
	     ^semantics.CExpr_Record_Update, ^semantics.CExpr_Interpolated_String, ^semantics.CExpr_Handle,
	     ^semantics.CExpr_Perform, ^semantics.CExpr_For, ^semantics.CExpr_Par:
		collect_uses_expr(analysis, stmt)
	}
}

// Handle assignment: $x = expr or name = expr (binding definition)
collect_uses_assign :: proc(analysis: ^Unused_Analysis, assign: ^semantics.CExpr_Assign) {
	target := assign.target
	value := assign.value

	collect_uses_expr(analysis, value)

	#partial switch t in target {
	case ^semantics.CExpr_Name:
		name := t.name.name
		name_str := base.intern_get(analysis.interner, name)

		if classify_name(name, analysis.interner) == .Reassignable {
			if _, exists := analysis.bindings[name]; exists {
				// Reassignment to existing $-var
				// Check for self-assignment: $x = $x
				if is_self_assignment(analysis, name, value) {
					diagnostics.collector_add_diag(analysis.collector,
						diagnostics.diag_noop_assignment(name_str, assign.span))
				}
				record_assignment(analysis, name, assign.span, value)
				// The RHS read of $x is a Self_Assign_Rhs use
				record_use(analysis, name, .Self_Assign_Rhs, assign.span)
			} else {
				// First assignment = declaration of $-var
				register_binding(analysis, name, t.span, is_top_level = false, is_pub = false)
				record_assignment(analysis, name, assign.span, value)
			}
		} else {
			// Immutable binding: x = expr
			if classify_name(name, analysis.interner) == .Wildcard {
				// _ = expr - check for pointless evaluation
				record_use(analysis, name, .Discard, assign.span)
			} else if _, exists := analysis.bindings[name]; !exists {
				register_binding(analysis, name, t.span, is_top_level = false, is_pub = false)
			}
		}
	case ^semantics.CExpr_Int, ^semantics.CExpr_Float, ^semantics.CExpr_String, ^semantics.CExpr_Bool,
	     ^semantics.CExpr_Tag, ^semantics.CExpr_Nominal_Construct, ^semantics.CExpr_Record, ^semantics.CExpr_List,
	     ^semantics.CExpr_Call, ^semantics.CExpr_Method_Call, ^semantics.CExpr_Lambda, ^semantics.CExpr_Block,
	     ^semantics.CExpr_If, ^semantics.CExpr_Match, ^semantics.CExpr_BinOp, ^semantics.CExpr_PrefixOp,
	     ^semantics.CExpr_Field_Access, ^semantics.CExpr_Record_Update, ^semantics.CExpr_Assign,
	     ^semantics.CExpr_Return, ^semantics.CExpr_Crash, ^semantics.CExpr_Interpolated_String,
	     ^semantics.CExpr_Handle, ^semantics.CExpr_Perform, ^semantics.CExpr_For, ^semantics.CExpr_Par:
		collect_uses_expr(analysis, target)
	}
}

// Check if value is a self-assignment: $x = $x
is_self_assignment :: proc(analysis: ^Unused_Analysis, target_name: base.Intern_ID, value: semantics.CExpr) -> bool {
	name_expr, is_name := value.(^semantics.CExpr_Name)
	if !is_name do return false
	return name_expr.name.name == target_name
}

// Walk a pattern and register introduced bindings
collect_uses_pattern :: proc(analysis: ^Unused_Analysis, pattern: semantics.CPattern) {
	#partial switch p in pattern {
	case ^semantics.CPattern_Identifier:
		register_binding(analysis, p.name, p.span, is_top_level = false, is_pub = false)
	case ^semantics.CPattern_Wildcard:
		{}
	case ^semantics.CPattern_Tag:
		for &payload in p.payload {
			collect_uses_pattern(analysis, payload)
		}
	case ^semantics.CPattern_Record:
		for &field in p.fields {
			if field.binding != base.NO_NAME {
				register_binding(analysis, field.binding, field.span, is_top_level = false, is_pub = false)
			}
		}
	case ^semantics.CPattern_List:
		for &elem in p.elements {
			collect_uses_pattern(analysis, elem)
		}
	case ^semantics.CPattern_Destructure:
		collect_uses_pattern(analysis, p.inner)
	case ^semantics.CPattern_Int, ^semantics.CPattern_String, ^semantics.CPattern_Bool:
		{}
	case ^semantics.CPattern_Or:
		for alt in p.alternatives {
			collect_uses_pattern(analysis, alt)
		}
	}
}

// Record a field access on a record expression
record_field_access :: proc(analysis: ^Unused_Analysis, record_expr: semantics.CExpr, field: base.Intern_ID, span: base.Source_Span) {
	name_expr, is_name := record_expr.(^semantics.CExpr_Name)
	if !is_name do return

	name := name_expr.name.name
	if bi, ok := analysis.bindings[name]; ok {
		if _, has_spans := bi.field_accesses[field]; !has_spans {
			bi.field_accesses[field] = make([dynamic]base.Source_Span, 0, 2)
		}
		append(&bi.field_accesses[field], span)
		analysis.bindings[name] = bi

		mark_field_accessed(analysis, name, field)
	}
}

// Mark bindings that escape via function arguments
mark_args_escaped :: proc(analysis: ^Unused_Analysis, arg: semantics.CExpr) {
	#partial switch a in arg {
	case ^semantics.CExpr_Name:
		name := a.name.name
		record_use(analysis, name, .Escape_Fn_Arg, a.span)
		mark_escaped(analysis, name)
	case ^semantics.CExpr_Record:
		for &field in a.fields {
			mark_args_escaped(analysis, field.value)
		}
	case ^semantics.CExpr_Call:
		mark_args_escaped(analysis, a.callee)
		for &sub_arg in a.args {
			mark_args_escaped(analysis, sub_arg)
		}
	case ^semantics.CExpr_BinOp:
		mark_args_escaped(analysis, a.left)
		mark_args_escaped(analysis, a.right)
	case ^semantics.CExpr_Field_Access:
		mark_args_escaped(analysis, a.record)
	case ^semantics.CExpr_Int, ^semantics.CExpr_Float, ^semantics.CExpr_String, ^semantics.CExpr_Bool,
	     ^semantics.CExpr_Tag, ^semantics.CExpr_Nominal_Construct, ^semantics.CExpr_List,
	     ^semantics.CExpr_Method_Call, ^semantics.CExpr_Lambda, ^semantics.CExpr_Block, ^semantics.CExpr_If,
	     ^semantics.CExpr_Match, ^semantics.CExpr_PrefixOp, ^semantics.CExpr_Record_Update,
	     ^semantics.CExpr_Assign, ^semantics.CExpr_Return, ^semantics.CExpr_Crash,
	     ^semantics.CExpr_Interpolated_String, ^semantics.CExpr_Handle, ^semantics.CExpr_Perform,
	     ^semantics.CExpr_For, ^semantics.CExpr_Par:
	}
}

// Mark bindings that escape via return
mark_returned_bindings :: proc(analysis: ^Unused_Analysis, expr: semantics.CExpr) {
	#partial switch e in expr {
	case ^semantics.CExpr_Name:
		name := e.name.name
		record_use(analysis, name, .Escape_Return, e.span)
		mark_escaped(analysis, name)
	case ^semantics.CExpr_Record:
		for &field in e.fields {
			mark_returned_bindings(analysis, field.value)
		}
	case ^semantics.CExpr_Call:
		for &arg in e.args {
			mark_returned_bindings(analysis, arg)
		}
	case ^semantics.CExpr_Int, ^semantics.CExpr_Float, ^semantics.CExpr_String, ^semantics.CExpr_Bool,
	     ^semantics.CExpr_Tag, ^semantics.CExpr_Nominal_Construct, ^semantics.CExpr_List,
	     ^semantics.CExpr_Method_Call, ^semantics.CExpr_Lambda, ^semantics.CExpr_Block, ^semantics.CExpr_If,
	     ^semantics.CExpr_Match, ^semantics.CExpr_BinOp, ^semantics.CExpr_PrefixOp, ^semantics.CExpr_Field_Access,
	     ^semantics.CExpr_Record_Update, ^semantics.CExpr_Assign, ^semantics.CExpr_Return, ^semantics.CExpr_Crash,
	     ^semantics.CExpr_Interpolated_String, ^semantics.CExpr_Handle, ^semantics.CExpr_Perform,
	     ^semantics.CExpr_For, ^semantics.CExpr_Par:
	}
}

// Mark bindings that escape via perform
mark_perform_args_escaped :: proc(analysis: ^Unused_Analysis, arg: semantics.CExpr) {
	#partial switch a in arg {
	case ^semantics.CExpr_Name:
		name := a.name.name
		record_use(analysis, name, .Escape_Perform, a.span)
		mark_escaped(analysis, name)
	case ^semantics.CExpr_Record:
		for &field in a.fields {
			mark_perform_args_escaped(analysis, field.value)
		}
	case ^semantics.CExpr_Int, ^semantics.CExpr_Float, ^semantics.CExpr_String, ^semantics.CExpr_Bool,
	     ^semantics.CExpr_Tag, ^semantics.CExpr_Nominal_Construct, ^semantics.CExpr_List,
	     ^semantics.CExpr_Call, ^semantics.CExpr_Method_Call, ^semantics.CExpr_Lambda, ^semantics.CExpr_Block,
	     ^semantics.CExpr_If, ^semantics.CExpr_Match, ^semantics.CExpr_BinOp, ^semantics.CExpr_PrefixOp,
	     ^semantics.CExpr_Field_Access, ^semantics.CExpr_Record_Update, ^semantics.CExpr_Assign,
	     ^semantics.CExpr_Return, ^semantics.CExpr_Crash, ^semantics.CExpr_Interpolated_String,
	     ^semantics.CExpr_Handle, ^semantics.CExpr_Perform, ^semantics.CExpr_For, ^semantics.CExpr_Par:
	}
}

// ============================================================
// Phase 2: Check - emit diagnostics for unused bindings
// ============================================================

check_unused :: proc(analysis: ^Unused_Analysis) {
	// Check imports
	check_unused_imports(analysis)

	// Collect bindings into a sorted slice for deterministic output order
	binding_keys: [dynamic]base.Intern_ID
	binding_keys.allocator = context.allocator
	for name, bi in analysis.bindings {
		append(&binding_keys, name)
	}

	// Sort by source span start position for deterministic output
	for i in 1..<len(binding_keys) {
		key := binding_keys[i]
		bi_i := analysis.bindings[key]
		j := i - 1
		for j >= 0 {
			bi_j := analysis.bindings[binding_keys[j]]
			if bi_i.span.start < bi_j.span.start {
				binding_keys[j + 1] = binding_keys[j]
				j -= 1
			} else {
				break
			}
		}
		binding_keys[j + 1] = key
	}

	for name in binding_keys {
		bi := analysis.bindings[name]
		if bi.classification == .Contradictory do continue
		if bi.classification == .Wildcard do continue

		// Skip if shadowed (shadowing error takes priority)
		if _, is_shadowed := analysis.shadowed_names[name]; is_shadowed do continue

		if bi.classification == .Reassignable {
			check_reassignable_var(analysis, name, bi)
		} else {
			check_immutable_binding(analysis, name, bi)
		}
	}
	delete(binding_keys)

	// Check record fields
	check_unused_record_fields(analysis)
}

check_unused_imports :: proc(analysis: ^Unused_Analysis) {
	for ii in analysis.imports {
		if !ii.used {
			name_str := base.intern_get(analysis.interner, ii.name)
			module_str := base.intern_get(analysis.interner, ii.module_name)
			diagnostics.collector_add_diag(analysis.collector,
				diagnostics.diag_unused_import(name_str, module_str, ii.span))
		}
	}
}

check_immutable_binding :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, bi: Binding_Info) {
	name_str := base.intern_get(analysis.interner, name)

	has_essential_use := binding_has_essential_use(bi)

	if !has_essential_use {
		// _-prefixed bindings are exempt from unused errors
		if bi.classification == .Underscore do return

		if bi.is_top_level {
			if !bi.is_pub && !bi.is_effectful {
				diagnostics.collector_add_diag(analysis.collector,
					diagnostics.diag_unused_binding(name_str, "", bi.span))
			}
			return
		}

		diagnostics.collector_add_diag(analysis.collector,
			diagnostics.diag_unused_binding(name_str, "", bi.span))
		return
	}

	// Check for pointless evaluation: _ = pureExpr
	if bi.classification == .Wildcard {
		for use in bi.use_sites {
			if use.kind == .Discard {
				// Pipeline integration will use Type_Store to determine
				// if the RHS is pure vs effectful for the pointless eval warning
				// TODO: implement pointless evaluation diagnostic
			}
		}
	}
	return
}

binding_has_essential_use :: proc(bi: Binding_Info) -> bool {
	for use in bi.use_sites {
		#partial switch use.kind {
		case .Read, .Field_Access, .Escape_Fn_Arg, .Escape_Return, .Escape_Perform:
			return true
		case .Self_Assign_Rhs, .Discard:
			{}
		}
	}
	return false
}

check_reassignable_var :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, bi: Binding_Info) {
	name_str := base.intern_get(analysis.interner, name)

	if len(bi.assignments) == 0 do return

	// Check each assignment for overwrite-before-read
	for i in 0..<len(bi.assignments) {
		assign := bi.assignments[i]

		// Check if this assignment is overwritten before any read
		if i < len(bi.assignments) - 1 {
			next_assign := bi.assignments[i + 1]
			if !assignment_has_read_before(analysis, name, assign.span, next_assign.span) {
				assign_no := i + 1
				diagnostics.collector_add_diag(analysis.collector,
					diagnostics.diag_unused_assignment(name_str, assign_no, "Value is overwritten before read.", assign.span))
			}
		} else {
			// Last assignment: check if final value is consumed
			if !bi.escaped && !binding_has_essential_use(bi) {
				// Loop exit exemption
				if assign.is_in_loop && has_essential_reads_in_loop(analysis, name, bi) {
					continue
				}
				assign_no := len(bi.assignments)
				diagnostics.collector_add_diag(analysis.collector,
					diagnostics.diag_unused_assignment(name_str, assign_no, "Final value is never consumed.", assign.span))
			}
		}
	}

	// If the $-var has no uses at all and is not _-prefixed, also emit unused binding
	if !binding_has_essential_use(bi) && bi.classification != .Underscore && !bi.is_top_level {
		// Only emit if there are no assignment-level errors already
		// (avoid double-reporting)
		if len(bi.assignments) == 1 && !bi.assignments[0].is_in_loop {
			// Single assignment with no reads = unused binding
			diagnostics.collector_add_diag(analysis.collector,
				diagnostics.diag_unused_binding(name_str, "", bi.span))
		}
	}
}

// Check if there is a read of the binding between two source positions
assignment_has_read_before :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, after_span: base.Source_Span, before_span: base.Source_Span) -> bool {
	for use in analysis.bindings[name].use_sites {
		if use.kind == .Read || use.kind == .Field_Access ||
		   use.kind == .Escape_Fn_Arg || use.kind == .Escape_Return || use.kind == .Escape_Perform {
			// Path-insensitive: if any read exists, consider it possibly read
			return true
		}
	}
	return false
}

// Check if a $-var has essential reads within a loop body
has_essential_reads_in_loop :: proc(analysis: ^Unused_Analysis, name: base.Intern_ID, bi: Binding_Info) -> bool {
	for use in bi.use_sites {
		#partial switch use.kind {
		case .Escape_Fn_Arg, .Escape_Return, .Escape_Perform:
			return true
		case .Read:
			// A read is essential if it appears as an argument to an effectful call
			// For v1, we use a conservative heuristic:
			// reads that are NOT only consumed by self-assignment are essential
			return true
		case .Field_Access, .Self_Assign_Rhs, .Discard:
		}
	}
	return false
}

check_unused_record_fields :: proc(analysis: ^Unused_Analysis) {
	for rfi in analysis.record_fields {
		bi, has_binding := analysis.bindings[rfi.binding_name]
		if has_binding && bi.escaped do continue

		if !rfi.accessed {
			field_str := base.intern_get(analysis.interner, rfi.field_name)
			diagnostics.collector_add_diag(analysis.collector,
				diagnostics.diag_unused_record_field(field_str, rfi.record_span, rfi.field_span))
		}
	}
}

// ============================================================
// Entry point: run the full unused analysis pass
// ============================================================

run_unused_analysis :: proc(cfile: semantics.CFile, interner: ^base.Intern_Table, collector: ^diagnostics.Diagnostic_Collector) {
	analysis: Unused_Analysis
	unused_analysis_init(&analysis, interner, collector)
	defer unused_analysis_destroy(&analysis)

	// Collect shadowed names from the diagnostic collector
	// (shadowing errors are emitted during typecheck; we need to suppress
	// unused-binding errors for shadowed names)
	for &diag in collector.diagnostics {
		if diag.title == "SHADOWING" && diag.shadowed_name != base.NO_NAME {
			analysis.shadowed_names[diag.shadowed_name] = true
		}
	}

	collect_uses_cfile(&analysis, cfile)
	check_unused(&analysis)
}
