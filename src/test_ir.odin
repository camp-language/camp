package camp

import "camp:base"
import "camp:ir"
import "camp:semantics"
import "camp:frontend"
import "camp:build"
import "camp:diagnostics"
import "core:testing"
import "core:mem"
import "core:strings"

lower_source :: proc(source: string) -> (ir.IR_Module, ^build.Compilation_Context, semantics.Type_Store) {
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc

	file := base.Source_File{path = "<ir-test>", contents = source, id = 0}
	lexer: frontend.Lexer
	frontend.lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

	parser: frontend.Parser
	frontend.parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
	surface := frontend.parser_parse_file(&parser)

	canon := semantics.canonicalize(surface, &ctx.interner, &ctx.collector)

	store: semantics.Type_Store
	semantics.type_store_init(&store, &ctx.interner, &ctx.collector)
	semantics.inject_prelude(&store)
	tfile := semantics.typecheck_file(canon, &store)

	mod := ir.lower_tfile(tfile, &store)
	return mod, ctx, store
}

teardown_lower :: proc(ctx: ^build.Compilation_Context, store: ^semantics.Type_Store) {
	semantics.type_store_destroy(store)
	build.context_destroy(ctx)
	free(ctx)
}

find_decl_fn :: proc(mod: ir.IR_Module, is_effectful: bool) -> ^ir.IR_Decl_Fn {
	for decl in mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if d.is_effectful == is_effectful {
				return d
			}
		case:
		}
	}
	return nil
}

@(test)
test_lower_int_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = 42")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_Literal_Int:
			testing.expect(t, expr.value == 42)
			testing.expect(t, expr.type.wasm_type == .I64)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_bool_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = True")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_Literal_Bool:
			testing.expect(t, expr.value == true)
			testing.expect(t, expr.type.wasm_type == .I32)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_float_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = 3.14")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_Literal_Float:
			testing.expect(t, expr.type.wasm_type == .F64)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_string_literal :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = \"hello\"")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_Literal_String:
			testing.expect(t, expr.type.wasm_type == .I32)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_binop :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = 1 + 2")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_BinOp:
			testing.expect(t, expr.op == .Add)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_if :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = if True { 1 } else { 2 }")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_If:
			testing.expect(t, expr.else_branch != nil)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_record :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("r = { name: \"Camp\", age: 1 }")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) == 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_Construct_Record:
			testing.expect(t, len(expr.fields) == 2)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_effect_decl :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("IO! : { println!: || -> Str }")
	defer teardown_lower(ctx, &store)

	io_found := false
	for eff in mod.effect_defs {
		io_name := base.intern_get(&ctx.interner, eff.name.name)
		if io_name == "IO" {
			io_found = true
			testing.expect(t, len(eff.operations) == 1)
		}
	}
	testing.expect(t, io_found)
}

@(test)
test_lower_effectful_const :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("main! = || { 42 }")
	defer teardown_lower(ctx, &store)

	fn_decl := find_decl_fn(mod, true)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, fn_decl.is_effectful == true)
	testing.expect(t, len(fn_decl.params) == 0)
}

@(test)
test_lower_lambda_as_fn :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("add = |x, y| x")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) >= 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Fn:
		testing.expect(t, len(decl.params) == 2)
		testing.expect(t, decl.is_effectful == false)
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_handle :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	found_handle := false
	for decl in mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			#partial switch expr in d.body {
			case ^ir.IR_Handle:
				found_handle = true
				testing.expect(t, len(expr.arms) == 1)
			case:
			}
		case:
		}
	}
	testing.expect(t, found_handle)
}

@(test)
test_lower_tag :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = Some(42)")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.decls) >= 1)
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Const:
		#partial switch expr in decl.value {
		case ^ir.IR_Construct_Tag:
			testing.expect(t, len(expr.payload) == 1)
		case:
			testing.expect(t, false)
		}
	case:
		testing.expect(t, false)
	}
}

@(test)
test_lower_string_table :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("x = \"hello\"")
	defer teardown_lower(ctx, &store)

	testing.expect(t, len(mod.string_table) >= 1)
}

contains_ir_let :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Let:
		return true
	case ^ir.IR_If:
		return contains_ir_let(e.condition) || contains_ir_let(e.then_branch) || contains_ir_let(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_let(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_let(e.left) || contains_ir_let(e.right)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_let(arg) do return true
		}
	case ^ir.IR_Return:
		return contains_ir_let(e.value)
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if contains_ir_let(f.value) do return true
		}
		return contains_ir_let(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if contains_ir_let(p) do return true
		}
	case ^ir.IR_Field_Access:
		return contains_ir_let(e.record)
	case ^ir.IR_Method_Call:
		if contains_ir_let(e.receiver) do return true
		for arg in e.args {
			if contains_ir_let(arg) do return true
		}
	case ^ir.IR_Handle:
		if contains_ir_let(e.body) do return true
		for arm in e.arms {
			if contains_ir_let(arm.body) do return true
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			if contains_ir_let(arg) do return true
		}
	case:
	}
	return false
}

contains_ir_call :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Call:
		return true
	case ^ir.IR_Closure_Call:
		return true
	case ^ir.IR_Let:
		return contains_ir_call(e.value) || contains_ir_call(e.body)
	case ^ir.IR_If:
		return contains_ir_call(e.condition) || contains_ir_call(e.then_branch) || contains_ir_call(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_call(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_call(e.left) || contains_ir_call(e.right)
	case ^ir.IR_Return:
		return contains_ir_call(e.value)
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if contains_ir_call(f.value) do return true
		}
		return contains_ir_call(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if contains_ir_call(p) do return true
		}
	case ^ir.IR_Field_Access:
		return contains_ir_call(e.record)
	case ^ir.IR_Method_Call:
		if contains_ir_call(e.receiver) do return true
		for arg in e.args {
			if contains_ir_call(arg) do return true
		}
	case ^ir.IR_Handle:
		if contains_ir_call(e.body) do return true
		for arm in e.arms {
			if contains_ir_call(arm.body) do return true
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			if contains_ir_call(arg) do return true
		}
	case:
	}
	return false
}

contains_ir_tail_call :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Tail_Call:
		return true
	case ^ir.IR_Let:
		return contains_ir_tail_call(e.value) || contains_ir_tail_call(e.body)
	case ^ir.IR_If:
		return contains_ir_tail_call(e.condition) || contains_ir_tail_call(e.then_branch) || contains_ir_tail_call(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_tail_call(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_tail_call(e.left) || contains_ir_tail_call(e.right)
	case ^ir.IR_Return:
		return contains_ir_tail_call(e.value)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_tail_call(arg) do return true
		}
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if contains_ir_tail_call(f.value) do return true
		}
		return contains_ir_tail_call(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if contains_ir_tail_call(p) do return true
		}
	case ^ir.IR_Field_Access:
		return contains_ir_tail_call(e.record)
	case ^ir.IR_Method_Call:
		if contains_ir_tail_call(e.receiver) do return true
		for arg in e.args {
			if contains_ir_tail_call(arg) do return true
		}
	case ^ir.IR_Handle:
		if contains_ir_tail_call(e.body) do return true
		for arm in e.arms {
			if contains_ir_tail_call(arm.body) do return true
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			if contains_ir_tail_call(arg) do return true
		}
	case:
	}
	return false
}

contains_ir_construct_record :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Construct_Record:
		return true
	case ^ir.IR_Let:
		return contains_ir_construct_record(e.value) || contains_ir_construct_record(e.body)
	case ^ir.IR_If:
		return contains_ir_construct_record(e.condition) || contains_ir_construct_record(e.then_branch) || contains_ir_construct_record(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_construct_record(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_construct_record(e.left) || contains_ir_construct_record(e.right)
	case ^ir.IR_Return:
		return contains_ir_construct_record(e.value)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_construct_record(arg) do return true
		}
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if contains_ir_construct_record(p) do return true
		}
	case ^ir.IR_Field_Access:
		return contains_ir_construct_record(e.record)
	case ^ir.IR_Method_Call:
		if contains_ir_construct_record(e.receiver) do return true
		for arg in e.args {
			if contains_ir_construct_record(arg) do return true
		}
	case ^ir.IR_Handle:
		if contains_ir_construct_record(e.body) do return true
		for arm in e.arms {
			if contains_ir_construct_record(arm.body) do return true
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			if contains_ir_construct_record(arg) do return true
		}
	case:
	}
	return false
}

@(test)
test_effect_lower_handle :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	result := ir.effect_lower(&mod, &ctx.interner, &ctx.collector, &store)

	found_let := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if contains_ir_let(d.body) {
				found_let = true
			}
		case:
		}
	}
	testing.expect(t, found_let)
}

@(test)
test_effect_lower_perform :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	result := ir.effect_lower(&mod, &ctx.interner, &ctx.collector, &store)

	found_call := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if contains_ir_call(d.body) {
				found_call = true
			}
		case:
		}
	}
	testing.expect(t, found_call)
}

@(test)
test_effect_lower_handler_fns :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	result := ir.effect_lower(&mod, &ctx.interner, &ctx.collector, &store)

	handler_count := 0
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(&ctx.interner, d.name.name)
			if strings.has_prefix(name_str, "handler_") {
				handler_count += 1
			}
		case:
		}
	}
	testing.expect(t, handler_count >= 1)
}

contains_ir_i32_load :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_I32_Load:
		return true
	case ^ir.IR_Let:
		return contains_ir_i32_load(e.value) || contains_ir_i32_load(e.body)
	case ^ir.IR_If:
		return contains_ir_i32_load(e.condition) || contains_ir_i32_load(e.then_branch) || contains_ir_i32_load(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_i32_load(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_i32_load(e.left) || contains_ir_i32_load(e.right)
	case ^ir.IR_Return:
		return contains_ir_i32_load(e.value)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_i32_load(arg) do return true
		}
	case ^ir.IR_Closure_Call:
		if contains_ir_i32_load(e.callee) do return true
		for arg in e.args {
			if contains_ir_i32_load(arg) do return true
		}
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if contains_ir_i32_load(f.value) do return true
		}
		return contains_ir_i32_load(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if contains_ir_i32_load(p) do return true
		}
	case ^ir.IR_Field_Access:
		return contains_ir_i32_load(e.record)
	case ^ir.IR_Method_Call:
		if contains_ir_i32_load(e.receiver) do return true
		for arg in e.args {
			if contains_ir_i32_load(arg) do return true
		}
	case ^ir.IR_Handle:
		if contains_ir_i32_load(e.body) do return true
		for arm in e.arms {
			if contains_ir_i32_load(arm.body) do return true
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			if contains_ir_i32_load(arg) do return true
		}
	case ^ir.IR_I32_Store:
		return contains_ir_i32_load(e.base) || contains_ir_i32_load(e.value)
	case:
	}
	return false
}

contains_ir_i32_store :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_I32_Store:
		return true
	case ^ir.IR_Let:
		return contains_ir_i32_store(e.value) || contains_ir_i32_store(e.body)
	case ^ir.IR_If:
		return contains_ir_i32_store(e.condition) || contains_ir_i32_store(e.then_branch) || contains_ir_i32_store(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_i32_store(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_i32_store(e.left) || contains_ir_i32_store(e.right)
	case ^ir.IR_Return:
		return contains_ir_i32_store(e.value)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_i32_store(arg) do return true
		}
	case ^ir.IR_Closure_Call:
		if contains_ir_i32_store(e.callee) do return true
		for arg in e.args {
			if contains_ir_i32_store(arg) do return true
		}
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if contains_ir_i32_store(f.value) do return true
		}
		return contains_ir_i32_store(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if contains_ir_i32_store(p) do return true
		}
	case ^ir.IR_Field_Access:
		return contains_ir_i32_store(e.record)
	case ^ir.IR_Method_Call:
		if contains_ir_i32_store(e.receiver) do return true
		for arg in e.args {
			if contains_ir_i32_store(arg) do return true
		}
	case ^ir.IR_Handle:
		if contains_ir_i32_store(e.body) do return true
		for arm in e.arms {
			if contains_ir_i32_store(arm.body) do return true
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			if contains_ir_i32_store(arg) do return true
		}
	case ^ir.IR_I32_Load:
		return contains_ir_i32_store(e.base)
	case:
	}
	return false
}

contains_ir_closure_call :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Closure_Call:
		return true
	case ^ir.IR_Let:
		return contains_ir_closure_call(e.value) || contains_ir_closure_call(e.body)
	case ^ir.IR_If:
		return contains_ir_closure_call(e.condition) || contains_ir_closure_call(e.then_branch) || contains_ir_closure_call(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_closure_call(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_closure_call(e.left) || contains_ir_closure_call(e.right)
	case ^ir.IR_Return:
		return contains_ir_closure_call(e.value)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_closure_call(arg) do return true
		}
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if contains_ir_closure_call(f.value) do return true
		}
		return contains_ir_closure_call(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if contains_ir_closure_call(p) do return true
		}
	case ^ir.IR_Field_Access:
		return contains_ir_closure_call(e.record)
	case ^ir.IR_Method_Call:
		if contains_ir_closure_call(e.receiver) do return true
		for arg in e.args {
			if contains_ir_closure_call(arg) do return true
		}
	case ^ir.IR_Handle:
		if contains_ir_closure_call(e.body) do return true
		for arm in e.arms {
			if contains_ir_closure_call(arm.body) do return true
		}
	case ^ir.IR_Perform:
		for arg in e.args {
			if contains_ir_closure_call(arg) do return true
		}
	case:
	}
	return false
}

has_camp_alloc_call :: proc(expr: ir.IR_Expr, alloc_id: base.Intern_ID) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Call:
		if e.callee.name == alloc_id do return true
		for arg in e.args {
			if has_camp_alloc_call(arg, alloc_id) do return true
		}
	case ^ir.IR_Let:
		return has_camp_alloc_call(e.value, alloc_id) || has_camp_alloc_call(e.body, alloc_id)
	case ^ir.IR_If:
		return has_camp_alloc_call(e.condition, alloc_id) || has_camp_alloc_call(e.then_branch, alloc_id) || has_camp_alloc_call(e.else_branch, alloc_id)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if has_camp_alloc_call(stmt, alloc_id) do return true
		}
	case ^ir.IR_BinOp:
		return has_camp_alloc_call(e.left, alloc_id) || has_camp_alloc_call(e.right, alloc_id)
	case ^ir.IR_Return:
		return has_camp_alloc_call(e.value, alloc_id)
	case ^ir.IR_Closure_Call:
		if has_camp_alloc_call(e.callee, alloc_id) do return true
		for arg in e.args {
			if has_camp_alloc_call(arg, alloc_id) do return true
		}
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if has_camp_alloc_call(f.value, alloc_id) do return true
		}
		return has_camp_alloc_call(e.rest, alloc_id)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if has_camp_alloc_call(p, alloc_id) do return true
		}
	case ^ir.IR_Field_Access:
		return has_camp_alloc_call(e.record, alloc_id)
	case ^ir.IR_Method_Call:
		if has_camp_alloc_call(e.receiver, alloc_id) do return true
		for arg in e.args {
			if has_camp_alloc_call(arg, alloc_id) do return true
		}
	case:
	}
	return false
}

has_camp_dealloc_call :: proc(expr: ir.IR_Expr, dealloc_id: base.Intern_ID) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Call:
		if e.callee.name == dealloc_id do return true
		for arg in e.args {
			if has_camp_dealloc_call(arg, dealloc_id) do return true
		}
	case ^ir.IR_Let:
		return has_camp_dealloc_call(e.value, dealloc_id) || has_camp_dealloc_call(e.body, dealloc_id)
	case ^ir.IR_If:
		return has_camp_dealloc_call(e.condition, dealloc_id) || has_camp_dealloc_call(e.then_branch, dealloc_id) || has_camp_dealloc_call(e.else_branch, dealloc_id)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if has_camp_dealloc_call(stmt, dealloc_id) do return true
		}
	case ^ir.IR_BinOp:
		return has_camp_dealloc_call(e.left, dealloc_id) || has_camp_dealloc_call(e.right, dealloc_id)
	case ^ir.IR_Return:
		return has_camp_dealloc_call(e.value, dealloc_id)
	case ^ir.IR_Closure_Call:
		if has_camp_dealloc_call(e.callee, dealloc_id) do return true
		for arg in e.args {
			if has_camp_dealloc_call(arg, dealloc_id) do return true
		}
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if has_camp_dealloc_call(f.value, dealloc_id) do return true
		}
		return has_camp_dealloc_call(e.rest, dealloc_id)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			if has_camp_dealloc_call(p, dealloc_id) do return true
		}
	case ^ir.IR_Field_Access:
		return has_camp_dealloc_call(e.record, dealloc_id)
	case ^ir.IR_Method_Call:
		if has_camp_dealloc_call(e.receiver, dealloc_id) do return true
		for arg in e.args {
			if has_camp_dealloc_call(arg, dealloc_id) do return true
		}
	case:
	}
	return false
}

effect_lower_source :: proc(source: string) -> (ir.IR_Module, ^build.Compilation_Context, semantics.Type_Store) {
	mod, ctx, store := lower_source(source)
	result := ir.effect_lower(&mod, &ctx.interner, &ctx.collector, &store)
	return result, ctx, store
}

@(test)
test_effect_lower_produces_handler_decls :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	handler_count := 0
	cont_count := 0
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(&ctx.interner, d.name.name)
			if strings.has_prefix(name_str, "handler_") || strings.has_prefix(name_str, "handler") {
				handler_count += 1
			}
			if strings.has_prefix(name_str, "_kc") {
				cont_count += 1
			}
		case:
		}
	}
	testing.expect(t, handler_count >= 1)
}

@(test)
test_effect_lower_perform_dispatches_via_i32_load :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	found_i32_load := false
	found_closure_call := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if d.is_effectful {
				if contains_ir_i32_load(d.body) { found_i32_load = true }
				if contains_ir_closure_call(d.body) { found_closure_call = true }
			}
		case:
		}
	}
	testing.expect(t, found_i32_load)
	testing.expect(t, found_closure_call)
}

@(test)
test_effect_lower_handle_evidence_record :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	alloc_id := base.intern(&ctx.interner, "camp_alloc")
	dealloc_id := base.intern(&ctx.interner, "camp_dealloc")

	found_alloc := false
	found_dealloc := false
	found_store := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if d.is_effectful {
				if has_camp_alloc_call(d.body, alloc_id) { found_alloc = true }
				if has_camp_dealloc_call(d.body, dealloc_id) { found_dealloc = true }
				if contains_ir_i32_store(d.body) { found_store = true }
			}
		case:
		}
	}
	testing.expect(t, found_alloc)
	testing.expect(t, found_store)
}

@(test)
test_effect_lower_handler_fn_has_env_and_ev_params :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	found := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(&ctx.interner, d.name.name)
			if strings.has_prefix(name_str, "handler_") || strings.has_prefix(name_str, "handler") {
				has_env := false
				has_ev := false
				for p in d.params {
					p_str := base.intern_get(&ctx.interner, p.name)
					if strings.has_prefix(p_str, "_env_") { has_env = true }
					if strings.has_prefix(p_str, "_ev_") { has_ev = true }
				}
				if has_env && has_ev {
					found = true
				}
			}
		case:
		}
	}
	testing.expect(t, found)
}

@(test)
test_effect_lower_handler_fn_count_matches_ops :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str, readln!: || -> Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}), .readln!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	handler_count := 0
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(&ctx.interner, d.name.name)
			if strings.has_prefix(name_str, "handler_") || strings.has_prefix(name_str, "handler") {
				handler_count += 1
			}
		case:
		}
	}
	testing.expect(t, handler_count >= 2)
}

@(test)
test_closure_convert_closure :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| |y| x")
	defer teardown_lower(ctx, &store)

	result := ir.closure_convert(&mod, &ctx.interner)

	found_record := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if contains_ir_construct_record(d.body) {
				found_record = true
			}
		case:
		}
	}
	testing.expect(t, found_record)
}

@(test)
test_closure_convert_creates_closed_fn :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| |y| x")
	defer teardown_lower(ctx, &store)

	original_count := len(mod.decls)
	result := ir.closure_convert(&mod, &ctx.interner)

	testing.expect(t, len(result.decls) > original_count)
}

@(test)
test_cps_transform_effectful_fn :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("main! = || { 42 }")
	defer teardown_lower(ctx, &store)

	result := ir.cps_transform(&mod, &ctx.interner)

	fn_decl := find_decl_fn(result, true)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, len(fn_decl.params) >= 1)
}

@(test)
test_cps_transform_return_becomes_tail_call :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("main! = || { 42 }")
	defer teardown_lower(ctx, &store)

	result := ir.cps_transform(&mod, &ctx.interner)

	fn_decl := find_decl_fn(result, true)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, contains_ir_tail_call(fn_decl.body) || contains_ir_closure_call(fn_decl.body))
}

@(test)
test_cps_transform_pure_fn_unchanged :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("add = |x, y| x")
	defer teardown_lower(ctx, &store)

	original_param_count := 0
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Fn:
		original_param_count = len(decl.params)
	case:
	}

	result := ir.cps_transform(&mod, &ctx.interner)

	fn_decl := find_decl_fn(result, false)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, len(fn_decl.params) == original_param_count)
}

has_dup_or_drop :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Dup:
		return true
	case ^ir.IR_Drop:
		return true
	case ^ir.IR_Let:
		if has_dup_or_drop(e.value) do return true
		return has_dup_or_drop(e.body)
	case ^ir.IR_Call:
		for arg in e.args {
			if has_dup_or_drop(arg) do return true
		}
	case ^ir.IR_BinOp:
		if has_dup_or_drop(e.left) do return true
		return has_dup_or_drop(e.right)
	case ^ir.IR_If:
		if has_dup_or_drop(e.condition) do return true
		if has_dup_or_drop(e.then_branch) do return true
		return has_dup_or_drop(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if has_dup_or_drop(stmt) do return true
		}
	case ^ir.IR_Return:
		return has_dup_or_drop(e.value)
	case:
	}
	return false
}

@(test)
test_rc_insert_dup_drop :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = || { a = 42; a + a }")
	defer teardown_lower(ctx, &store)

	ir.rc_insert(&mod, &ctx.interner)

	fn_decl := find_decl_fn(mod, false)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, has_dup_or_drop(fn_decl.body))
}

contains_ir_field_access :: proc(expr: ir.IR_Expr) -> bool {
	#partial switch e in expr {
	case ^ir.IR_Field_Access:
		return true
	case ^ir.IR_Let:
		if contains_ir_field_access(e.value) do return true
		return contains_ir_field_access(e.body)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_field_access(arg) do return true
		}
	case ^ir.IR_Closure_Call:
		if contains_ir_field_access(e.callee) do return true
		for arg in e.args {
			if contains_ir_field_access(arg) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_field_access(e.left) || contains_ir_field_access(e.right)
	case ^ir.IR_If:
		return contains_ir_field_access(e.condition) || contains_ir_field_access(e.then_branch) || contains_ir_field_access(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_field_access(stmt) do return true
		}
	case ^ir.IR_Return:
		return contains_ir_field_access(e.value)
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			if contains_ir_field_access(f.value) do return true
		}
		return contains_ir_field_access(e.rest)
	case:
	}
	return false
}

@(test)
test_closure_capture_free_var :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| |y| x")
	defer teardown_lower(ctx, &store)

	result := ir.closure_convert(&mod, &ctx.interner)

	has_env_access := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if contains_ir_field_access(d.body) {
				has_env_access = true
			}
		case:
		}
	}
	testing.expect(t, has_env_access)
}

@(test)
test_closure_closed_fn_has_params :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| |y| x")
	defer teardown_lower(ctx, &store)

	result := ir.closure_convert(&mod, &ctx.interner)

	found := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			has_cenv := false
			has_y := false
			for p in d.params {
				name_str := base.intern_get(&ctx.interner, p.name)
				if strings.contains(name_str, "_cenv") { has_cenv = true }
				if strings.contains(name_str, "y") { has_y = true }
			}
			if has_cenv && has_y {
				found = true
			}
		case:
		}
	}
	testing.expect(t, found)
}

contains_ir_resume :: proc(expr: ir.IR_Expr) -> bool {
	if expr == nil do return false
	#partial switch e in expr {
	case ^ir.IR_Resume:
		return true
	case ^ir.IR_Let:
		return contains_ir_resume(e.value) || contains_ir_resume(e.body)
	case ^ir.IR_If:
		return contains_ir_resume(e.condition) || contains_ir_resume(e.then_branch) || contains_ir_resume(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			if contains_ir_resume(stmt) do return true
		}
	case ^ir.IR_BinOp:
		return contains_ir_resume(e.left) || contains_ir_resume(e.right)
	case ^ir.IR_Return:
		return contains_ir_resume(e.value)
	case ^ir.IR_Call:
		for arg in e.args {
			if contains_ir_resume(arg) do return true
		}
	case ^ir.IR_Closure_Call:
		if contains_ir_resume(e.callee) do return true
		for arg in e.args {
			if contains_ir_resume(arg) do return true
		}
	case ^ir.IR_Closure:
		if contains_ir_resume(e.env) do return true
		if contains_ir_resume(e.body) do return true
	case:
	}
	return false
}

has_resume_with_ev :: proc(expr: ir.IR_Expr) -> bool {
	if expr == nil do return false
	#partial switch e in expr {
	case ^ir.IR_Resume:
		return e.ev != nil
	case ^ir.IR_Let:
		return has_resume_with_ev(e.value) || has_resume_with_ev(e.body)
	case ^ir.IR_If:
		return has_resume_with_ev(e.condition) || has_resume_with_ev(e.then_branch) || has_resume_with_ev(e.else_branch)
	case ^ir.IR_Closure:
		if has_resume_with_ev(e.env) do return true
		return has_resume_with_ev(e.body)
	case:
	}
	return false
}

continuation_has_ev_param :: proc(mod: ir.IR_Module, interner: ^base.Intern_Table) -> bool {
	for decl in mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(interner, d.name.name)
			if strings.has_prefix(name_str, "_kc") {
				for p in d.params {
					p_str := base.intern_get(interner, p.name)
					if strings.has_prefix(p_str, "_ev") {
						return true
					}
				}
			}
		case:
		}
	}
	return false
}

@(test)
test_effect_lower_produces_ir_resume :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	found_resume := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if contains_ir_resume(d.body) {
				found_resume = true
			}
		case:
		}
	}
	testing.expect(t, found_resume)
}

@(test)
test_effect_lower_resume_deep_has_ev :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	found := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if has_resume_with_ev(d.body) {
				found = true
			}
		case:
		}
	}
	testing.expect(t, found)
}

@(test)
test_effect_lower_deep_continuation_has_ev_param :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { IO.println(\"hi\") } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	testing.expect(t, continuation_has_ev_param(result, &ctx.interner))
}

// ── Helper: count ir.IR_Dup nodes ──────────────────────────────────────────────

count_ir_dup :: proc(expr: ir.IR_Expr) -> int {
	if expr == nil do return 0
	count := 0
	#partial switch e in expr {
	case ^ir.IR_Dup:
		count += 1
	case ^ir.IR_Let:
		count += count_ir_dup(e.value)
		count += count_ir_dup(e.body)
	case ^ir.IR_If:
		count += count_ir_dup(e.condition)
		count += count_ir_dup(e.then_branch)
		count += count_ir_dup(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			count += count_ir_dup(stmt)
		}
	case ^ir.IR_BinOp:
		count += count_ir_dup(e.left)
		count += count_ir_dup(e.right)
	case ^ir.IR_Call:
		for arg in e.args {
			count += count_ir_dup(arg)
		}
	case ^ir.IR_Closure_Call:
		count += count_ir_dup(e.callee)
		for arg in e.args {
			count += count_ir_dup(arg)
		}
	case ^ir.IR_Return:
		count += count_ir_dup(e.value)
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			count += count_ir_dup(f.value)
		}
		count += count_ir_dup(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			count += count_ir_dup(p)
		}
	case ^ir.IR_Field_Access:
		count += count_ir_dup(e.record)
	case:
	}
	return count
}

// ── Helper: count ir.IR_Drop nodes ─────────────────────────────────────────────

count_ir_drop :: proc(expr: ir.IR_Expr) -> int {
	if expr == nil do return 0
	count := 0
	#partial switch e in expr {
	case ^ir.IR_Drop:
		count += 1
	case ^ir.IR_Let:
		count += count_ir_drop(e.value)
		count += count_ir_drop(e.body)
	case ^ir.IR_If:
		count += count_ir_drop(e.condition)
		count += count_ir_drop(e.then_branch)
		count += count_ir_drop(e.else_branch)
	case ^ir.IR_Block:
		for stmt in e.statements {
			count += count_ir_drop(stmt)
		}
	case ^ir.IR_BinOp:
		count += count_ir_drop(e.left)
		count += count_ir_drop(e.right)
	case ^ir.IR_Call:
		for arg in e.args {
			count += count_ir_drop(arg)
		}
	case ^ir.IR_Closure_Call:
		count += count_ir_drop(e.callee)
		for arg in e.args {
			count += count_ir_drop(arg)
		}
	case ^ir.IR_Return:
		count += count_ir_drop(e.value)
	case ^ir.IR_Construct_Record:
		for f in e.fields {
			count += count_ir_drop(f.value)
		}
		count += count_ir_drop(e.rest)
	case ^ir.IR_Construct_Tag:
		for p in e.payload {
			count += count_ir_drop(p)
		}
	case ^ir.IR_Field_Access:
		count += count_ir_drop(e.record)
	case:
	}
	return count
}

// ── Pipeline helper wrappers ────────────────────────────────────────────────

closure_convert_source :: proc(source: string) -> (ir.IR_Module, ^build.Compilation_Context, semantics.Type_Store) {
	mod, ctx, store := lower_source(source)
	mod = ir.effect_lower(&mod, &ctx.interner, &ctx.collector, &store)
	result := ir.closure_convert(&mod, &ctx.interner)
	return result, ctx, store
}

cps_source :: proc(source: string) -> (ir.IR_Module, ^build.Compilation_Context, semantics.Type_Store) {
	mod, ctx, store := lower_source(source)
	mod = ir.effect_lower(&mod, &ctx.interner, &ctx.collector, &store)
	mod = ir.closure_convert(&mod, &ctx.interner)
	result := ir.cps_transform(&mod, &ctx.interner)
	return result, ctx, store
}

find_decl_fn_by_name :: proc(mod: ir.IR_Module, name_str: string, interner: ^base.Intern_Table) -> ^ir.IR_Decl_Fn {
	for decl in mod.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if base.intern_get(interner, d.name.name) == name_str {
				return d
			}
		case:
		}
	}
	return nil
}

// ═══════════════════════════════════════════════════════════════════════════════
// Phase 6 – effect_lower tests
// ═══════════════════════════════════════════════════════════════════════════════

@(test)
test_effect_lower_nested_handlers :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nState! : { get!: || -> I64 }\nmain! = handle State in { handle IO in { 42 } with { .println!(resume) => resume({}) } } with { .get!(resume) => resume(0) }")
	defer teardown_lower(ctx, &store)

	handler_count := 0
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(&ctx.interner, d.name.name)
			if strings.has_prefix(name_str, "handler") {
				handler_count += 1
			}
		case:
		}
	}
	testing.expect(t, handler_count >= 2)
}

@(test)
test_effect_lower_multi_arm_perform :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str, readln!: || -> Str }\nmain! = handle IO in { IO.println(\"hi\"); IO.readln() } with { .println!(resume) => resume({}), .readln!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	load_count := 0
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if d.is_effectful && contains_ir_i32_load(d.body) {
				load_count += 1
			}
		case:
		}
	}
	testing.expect(t, load_count >= 1)
}

@(test)
test_effect_lower_scheduler_passthrough :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"main! = { 42 }")
	defer teardown_lower(ctx, &store)

	handler_count := 0
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			name_str := base.intern_get(&ctx.interner, d.name.name)
			if strings.has_prefix(name_str, "handler") {
				handler_count += 1
			}
		case:
		}
	}
	testing.expect(t, handler_count == 0)
}

@(test)
test_effect_lower_handle_removes_ir_handle :: proc(t: ^testing.T) {
	result, ctx, store := effect_lower_source(
		"IO! : { println!: || -> Str }\nmain! = handle IO in { 42 } with { .println!(resume) => resume({}) }")
	defer teardown_lower(ctx, &store)

	found_handle := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if d.is_effectful {
				#partial switch expr in d.body {
				case ^ir.IR_Handle:
					found_handle = true
				case:
				}
			}
		case:
		}
	}
	testing.expect(t, !found_handle)
}

// ═══════════════════════════════════════════════════════════════════════════════
// Phase 6 – ir.closure_convert tests
// ═══════════════════════════════════════════════════════════════════════════════

@(test)
test_closure_convert_no_free_vars :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| x + 1")
	defer teardown_lower(ctx, &store)

	result := ir.closure_convert(&mod, &ctx.interner)

	found_cenv := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			for p in d.params {
				p_str := base.intern_get(&ctx.interner, p.name)
				if strings.contains(p_str, "_cenv") { found_cenv = true }
			}
		case:
		}
	}
	testing.expect(t, !found_cenv)
}

@(test)
test_closure_convert_multi_free_var :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| |y| |z| x + y + z")
	defer teardown_lower(ctx, &store)

	result := ir.closure_convert(&mod, &ctx.interner)

	field_access_count := 0
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if contains_ir_field_access(d.body) {
				field_access_count += 1
			}
		case:
		}
	}
	testing.expect(t, field_access_count >= 1)
}

@(test)
test_closure_convert_produces_record :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| |y| x")
	defer teardown_lower(ctx, &store)

	result := ir.closure_convert(&mod, &ctx.interner)

	found_record := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if contains_ir_construct_record(d.body) {
				found_record = true
			}
		case:
		}
	}
	testing.expect(t, found_record)
}

@(test)
test_closure_convert_env_param_name :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = |x| |y| x")
	defer teardown_lower(ctx, &store)

	result := ir.closure_convert(&mod, &ctx.interner)

	found := false
	for decl in result.decls {
		#partial switch d in decl {
		case ^ir.IR_Decl_Fn:
			if len(d.params) > 0 {
				first_param := base.intern_get(&ctx.interner, d.params[0].name)
				if strings.contains(first_param, "_cenv") {
					found = true
				}
			}
		case:
		}
	}
	testing.expect(t, found)
}

// ═══════════════════════════════════════════════════════════════════════════════
// Phase 6 – ir.cps_transform tests
// ═══════════════════════════════════════════════════════════════════════════════

@(test)
test_cps_transform_adds_k_param :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("main! = || { 42 }")
	defer teardown_lower(ctx, &store)

	result := ir.cps_transform(&mod, &ctx.interner)

	fn_decl := find_decl_fn(result, true)
	testing.expect(t, fn_decl != nil)
	has_k := false
	for p in fn_decl.params {
		p_str := base.intern_get(&ctx.interner, p.name)
		if strings.contains(p_str, "_k") { has_k = true }
	}
	testing.expect(t, has_k)
}

@(test)
test_cps_transform_pure_fn_no_k_param :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("add = |x, y| x")
	defer teardown_lower(ctx, &store)

	original_param_count := 0
	#partial switch decl in mod.decls[0] {
	case ^ir.IR_Decl_Fn:
		original_param_count = len(decl.params)
	case:
	}

	result := ir.cps_transform(&mod, &ctx.interner)

	fn_decl := find_decl_fn(result, false)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, len(fn_decl.params) == original_param_count)
}

@(test)
test_cps_transform_return_is_closure_call :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("main! = || { 42 }")
	defer teardown_lower(ctx, &store)

	result := ir.cps_transform(&mod, &ctx.interner)

	fn_decl := find_decl_fn(result, true)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, contains_ir_closure_call(fn_decl.body) || contains_ir_tail_call(fn_decl.body))
}

// ═══════════════════════════════════════════════════════════════════════════════
// Phase 6 – ir.rc_insert tests
// ═══════════════════════════════════════════════════════════════════════════════

@(test)
test_rc_insert_single_use_no_dup :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = || { a = 42; a }")
	defer teardown_lower(ctx, &store)

	ir.rc_insert(&mod, &ctx.interner)

	fn_decl := find_decl_fn(mod, false)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, count_ir_dup(fn_decl.body) == 0)
}

@(test)
test_rc_insert_multi_use_has_dup :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = || { a = 42; a + a }")
	defer teardown_lower(ctx, &store)

	ir.rc_insert(&mod, &ctx.interner)

	fn_decl := find_decl_fn(mod, false)
	testing.expect(t, fn_decl != nil)
	testing.expect(t, count_ir_dup(fn_decl.body) >= 1)
}

@(test)
test_rc_insert_has_drop :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = || { a = 42; a + a }")
	defer teardown_lower(ctx, &store)

	ir.rc_insert(&mod, &ctx.interner)

	fn_decl := find_decl_fn(mod, false)
	testing.expect(t, fn_decl != nil)
	// a = 42 is I64 (not heap-allocated), so no drop should be emitted
	testing.expect(t, count_ir_drop(fn_decl.body) == 0)
	// Verify dups ARE inserted (the real RC signal)
	testing.expect(t, count_ir_dup(fn_decl.body) >= 1)
}

@(test)
test_rc_insert_heap_drop :: proc(t: ^testing.T) {
	// Construct IR directly: let x = construct_record(...) in 42
	// where x is heap-typed and never used — should emit 1 drop
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc
	defer {
		build.context_destroy(ctx)
		free(ctx)
	}

	heap_type := base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true}
	int_type := base.IR_Type{wasm_type = .I64, type_id = base.Type_Var_ID(0)}

	x_name := base.intern(&ctx.interner, "x")

	// value: IR_Construct_Record with empty fields
	record := new(ir.IR_Construct_Record)
	record^ = ir.IR_Construct_Record{
		fields = make([dynamic]ir.IR_Record_Field, 0),
		rest = nil,
		type = heap_type,
		span = base.Source_Span{},
	}

	// body: IR_Literal_Int(42)
	lit := new(ir.IR_Literal_Int)
	lit^ = ir.IR_Literal_Int{value = 42, type = int_type, span = base.Source_Span{}}

	// let x = record in 42
	let_expr := new(ir.IR_Let)
	let_expr^ = ir.IR_Let{
		binding = x_name,
		type = heap_type,
		value = ir.IR_Expr(record),
		body = ir.IR_Expr(lit),
		span = base.Source_Span{},
	}

	// Wrap in a function
	fn_body := ir.IR_Expr(let_expr)
	fn_decl := new(ir.IR_Decl_Fn)
	fn_decl^ = ir.IR_Decl_Fn{
		name = base.Canonical_Name{module = base.NO_NAME, name = x_name},
		is_effectful = false,
		params = make([dynamic]ir.IR_Param, 0),
		return_type = int_type,
		effect_row = base.IR_Type{},
		effects = make([dynamic]base.Canonical_Name, 0),
		body = fn_body,
		span = base.Source_Span{},
	}

	mod := ir.IR_Module{
		decls = make([dynamic]ir.IR_Decl, 1),
		effect_defs = make([dynamic]ir.IR_Effect_Def, 0),
		string_table = make([dynamic]ir.String_Table_Entry, 0),
	}
	mod.decls[0] = ir.IR_Decl(fn_decl)

	ir.rc_insert(&mod, &ctx.interner)

	// x is heap-typed with 0 uses — should emit 1 drop
	drop_count := count_ir_drop(fn_decl.body)
	testing.expect(t, drop_count == 1)
}

@(test)
test_rc_insert_branch_independent :: proc(t: ^testing.T) {
	mod, ctx, store := lower_source("f = || { a = 42; if True { a + a } else { a + a } }")
	defer teardown_lower(ctx, &store)

	ir.rc_insert(&mod, &ctx.interner)

	fn_decl := find_decl_fn(mod, false)
	testing.expect(t, fn_decl != nil)
	// Each branch uses `a` twice (a + a), so each branch should get a dup
	testing.expect(t, has_dup_or_drop(fn_decl.body))
}

@(test)
test_rc_insert_branch_heap_drop :: proc(t: ^testing.T) {
	// Construct IR: let x = record in if True then 1 else 2
	// x is heap-typed, used in neither branch — each branch should emit a drop
	ctx: ^build.Compilation_Context = new(build.Compilation_Context)
	alloc := build.context_init(ctx)
	context.allocator = alloc
	defer {
		build.context_destroy(ctx)
		free(ctx)
	}

	heap_type := base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0), is_heap = true}
	int_type := base.IR_Type{wasm_type = .I64, type_id = base.Type_Var_ID(0)}
	bool_type := base.IR_Type{wasm_type = .I32, type_id = base.Type_Var_ID(0)}

	x_name := base.intern(&ctx.interner, "x")

	// value: IR_Construct_Record
	record := new(ir.IR_Construct_Record)
	record^ = ir.IR_Construct_Record{
		fields = make([dynamic]ir.IR_Record_Field, 0),
		rest = nil,
		type = heap_type,
		span = base.Source_Span{},
	}

	// condition: True
	cond := new(ir.IR_Literal_Bool)
	cond^ = ir.IR_Literal_Bool{value = true, type = bool_type, span = base.Source_Span{}}

	// then: 1
	then_lit := new(ir.IR_Literal_Int)
	then_lit^ = ir.IR_Literal_Int{value = 1, type = int_type, span = base.Source_Span{}}

	// else: 2
	else_lit := new(ir.IR_Literal_Int)
	else_lit^ = ir.IR_Literal_Int{value = 2, type = int_type, span = base.Source_Span{}}

	// if True then 1 else 2
	if_expr := new(ir.IR_If)
	if_expr^ = ir.IR_If{
		condition = ir.IR_Expr(cond),
		then_branch = ir.IR_Expr(then_lit),
		else_branch = ir.IR_Expr(else_lit),
		type = int_type,
		span = base.Source_Span{},
	}

	// let x = record in if ...
	let_expr := new(ir.IR_Let)
	let_expr^ = ir.IR_Let{
		binding = x_name,
		type = heap_type,
		value = ir.IR_Expr(record),
		body = ir.IR_Expr(if_expr),
		span = base.Source_Span{},
	}

	fn_body := ir.IR_Expr(let_expr)
	fn_decl := new(ir.IR_Decl_Fn)
	fn_decl^ = ir.IR_Decl_Fn{
		name = base.Canonical_Name{module = base.NO_NAME, name = x_name},
		is_effectful = false,
		params = make([dynamic]ir.IR_Param, 0),
		return_type = int_type,
		effect_row = base.IR_Type{},
		effects = make([dynamic]base.Canonical_Name, 0),
		body = fn_body,
		span = base.Source_Span{},
	}

	mod := ir.IR_Module{
		decls = make([dynamic]ir.IR_Decl, 1),
		effect_defs = make([dynamic]ir.IR_Effect_Def, 0),
		string_table = make([dynamic]ir.String_Table_Entry, 0),
	}
	mod.decls[0] = ir.IR_Decl(fn_decl)

	ir.rc_insert(&mod, &ctx.interner)

	// x is heap-typed, used in neither branch — each branch should emit 1 drop
	drop_count := count_ir_drop(fn_decl.body)
	testing.expect(t, drop_count == 2)
}
