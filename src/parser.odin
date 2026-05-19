#+feature dynamic-literals
package camp

import "core:strings"

Binding_Power :: int

PREFIX_BP :map[Token_Kind]Binding_Power = {
	.Minus  = 7,
	.Kw_Not = 7,
}

INFIX_BP :map[Token_Kind][2]Binding_Power = {
	.Kw_Or        = {1, 2},
	.Kw_And       = {3, 4},
	.Eq_Eq        = {5, 6},
	.Bang_Eq      = {5, 6},
	.Lt           = {5, 6},
	.Gt           = {5, 6},
	.Lt_Eq        = {5, 6},
	.Gt_Eq        = {5, 6},
	.Plus         = {9, 10},
	.Minus        = {9, 10},
	.Star         = {11, 12},
	.Slash        = {11, 12},
	.Percent      = {11, 12},
	.Caret        = {13, 14},
}

Parser :: struct {
	lexer:     ^Lexer,
	current:   Token,
	collector: ^Diagnostic_Collector,
	intern:    ^Intern_Table,
}

parser_init :: proc(p: ^Parser, lexer: ^Lexer, collector: ^Diagnostic_Collector, table: ^Intern_Table) {
	p.lexer = lexer
	p.collector = collector
	p.intern = table
	p.current = lexer_next(lexer)
}

parser_advance :: proc(p: ^Parser) -> Token {
	prev := p.current
	p.current = lexer_next(p.lexer)
	return prev
}

parser_expect :: proc(p: ^Parser, kind: Token_Kind) -> Token {
	if p.current.kind == kind {
		return parser_advance(p)
	}
	collector_add_diag(p.collector, diag_expected_token(kind, p.current, p.current.span))
	parser_advance(p)
	return Token{kind = kind, span = p.current.span}
}

expr_span_start :: proc(expr: Expr) -> int {
	switch e in expr {
	case ^Expr_Int:               return e.span.start
	case ^Expr_Float:             return e.span.start
	case ^Expr_String:            return e.span.start
	case ^Expr_Bool:              return e.span.start
	case ^Expr_Identifier:        return e.span.start
	case ^Expr_Dollar_Identifier: return e.span.start
	case ^Expr_PrefixOp:          return e.span.start
	case ^Expr_BinOp:             return e.span.start
	case ^Expr_Lambda:            return e.span.start
	case ^Expr_Block:             return e.span.start
	case ^Expr_If:                return e.span.start
	case ^Expr_Match:             return e.span.start
	case ^Expr_Tag:               return e.span.start
	case ^Expr_Call:              return e.span.start
	case ^Expr_Field_Access:      return e.span.start
	case ^Expr_Method_Call:       return e.span.start
	case ^Expr_Record:            return e.span.start
	case ^Expr_Record_Update:     return e.span.start
	case ^Expr_List:              return e.span.start
	case ^Expr_Assign:            return e.span.start
	case ^Expr_Return:            return e.span.start
	case ^Expr_Crash:             return e.span.start
	case ^Expr_Interpolate:       return e.span.start
	case ^Expr_Handle:            return e.span.start
	case:                         return 0
	}
}

right_span_end :: proc(expr: Expr) -> int {
	switch e in expr {
	case ^Expr_Int:               return e.span.end
	case ^Expr_Float:             return e.span.end
	case ^Expr_String:            return e.span.end
	case ^Expr_Bool:              return e.span.end
	case ^Expr_Identifier:        return e.span.end
	case ^Expr_Dollar_Identifier: return e.span.end
	case ^Expr_PrefixOp:          return e.span.end
	case ^Expr_BinOp:             return e.span.end
	case ^Expr_Lambda:            return e.span.end
	case ^Expr_Block:             return e.span.end
	case ^Expr_If:                return e.span.end
	case ^Expr_Match:             return e.span.end
	case ^Expr_Tag:               return e.span.end
	case ^Expr_Call:              return e.span.end
	case ^Expr_Field_Access:      return e.span.end
	case ^Expr_Method_Call:       return e.span.end
	case ^Expr_Record:            return e.span.end
	case ^Expr_Record_Update:     return e.span.end
	case ^Expr_List:              return e.span.end
	case ^Expr_Assign:            return e.span.end
	case ^Expr_Return:            return e.span.end
	case ^Expr_Crash:             return e.span.end
	case ^Expr_Interpolate:       return e.span.end
	case ^Expr_Handle:            return e.span.end
	case:                         return 0
	}
}

parser_parse_file :: proc(p: ^Parser) -> File {
	file: File
	file.path = ""
	file.decls = make([dynamic]Decl, 0, 32)

	for p.current.kind != .Eof {
		decl := parser_parse_decl(p)
		append(&file.decls, decl)
	}

	return file
}

parser_parse_decl :: proc(p: ^Parser) -> Decl {
	is_pub := false
	if p.current.kind == .Upper_Id && p.current.text == "pub" {
		parser_advance(p)
		is_pub = true
	}

	#partial switch p.current.kind {
	case .Kw_Effect:
		return parser_parse_effect_decl(p, is_pub)
	case .Kw_Trait:
		return parser_parse_trait_decl(p, is_pub)
	case .Kw_Alias:
		return parser_parse_alias_decl(p, is_pub)
	case .Kw_Import, .Kw_Unsafe:
		return parser_parse_import_decl(p, is_pub)
	case .Kw_Test:
		return parser_parse_test_decl(p)
	case .Kw_Expect:
		return parser_parse_expect_decl(p)
	case:
		return parser_parse_const_decl(p, is_pub)
	}
}

parser_parse_const_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
	start_span := p.current.span

	name := parser_advance(p)
	name_text := name.text

	is_effectful := false
	if p.current.kind == .Bang {
		is_effectful = true
		parser_advance(p)
		name_text = strings.concatenate({name.text, "!"}, context.allocator)
	}

	name_id := intern(p.intern, name_text)

	type_ann: ^Type = nil
	if p.current.kind == .Colon {
		parser_advance(p)
		type_ann = parser_parse_type(p)
	}

	parser_expect(p, .Eq)
	body := parser_parse_expr(p)

	decl := new(Decl_Const)
	decl^ = Decl_Const{
		name = name_id,
		is_pub = is_pub,
		is_effectful = is_effectful,
		body = body,
		type_ann = type_ann,
		span = Source_Span{file_id = start_span.file_id, start = start_span.start, end = p.current.span.end},
	}
	return decl
}

parser_parse_expr :: proc(p: ^Parser) -> Expr {
	return parser_parse_expr_bp(p, 0)
}

parser_parse_expr_bp :: proc(p: ^Parser, min_bp: Binding_Power) -> Expr {
	left := parser_parse_prefix(p)

	for {
		if p.current.kind == .Eof { break }

		right_bp: Binding_Power
		if bps, ok := INFIX_BP[p.current.kind]; ok {
			right_bp = bps[1]
			if bps[0] < min_bp { break }
		} else {
			break
		}

		op := parser_advance(p)
		right := parser_parse_expr_bp(p, right_bp)

		binop := new(Expr_BinOp)
		binop^ = Expr_BinOp{
			op = op.kind,
			left = left,
			right = right,
			span = Source_Span{file_id = op.span.file_id, start = expr_span_start(left), end = right_span_end(right)},
		}
		left = binop
	}

	return left
}

parser_parse_prefix :: proc(p: ^Parser) -> Expr {
	tok := p.current

	#partial switch tok.kind {
	case .Int_Literal:
		parser_advance(p)
		e := new(Expr_Int)
		e^ = Expr_Int{value = tok.int_value, span = tok.span}
		return e

	case .Float_Literal:
		parser_advance(p)
		e := new(Expr_Float)
		e^ = Expr_Float{value = tok.f64_value, span = tok.span}
		return e

	case .String_Literal:
		parser_advance(p)
		e := new(Expr_String)
		e^ = Expr_String{value = tok.text, span = tok.span}
		return e

	case .Kw_True:
		parser_advance(p)
		e := new(Expr_Bool)
		e^ = Expr_Bool{value = true, span = tok.span}
		return e

	case .Kw_False:
		parser_advance(p)
		e := new(Expr_Bool)
		e^ = Expr_Bool{value = false, span = tok.span}
		return e

	case .Upper_Id:
		return parser_parse_tag_or_call(p)

	case .Identifier:
		return parser_parse_identifier_expr(p)

	case .Dollar:
		parser_advance(p)
		name := parser_expect(p, .Identifier)
		e := new(Expr_Dollar_Identifier)
		e^ = Expr_Dollar_Identifier{name = intern(p.intern, name.text), span = tok.span}
		return e

	case .Pipe:
		return parser_parse_lambda(p)

	case .LBrace:
		return parser_parse_block_or_record(p)

	case .LBrack:
		return parser_parse_list(p)

	case .Kw_If:
		return parser_parse_if(p)

	case .Kw_Match:
		return parser_parse_match(p)

	case .Kw_Handle, .Kw_Intercept:
		return parser_parse_handle(p)

	case .LParen:
		parser_advance(p)
		expr := parser_parse_expr(p)
		parser_expect(p, .RParen)
		return expr

	case .Minus, .Kw_Not:
		parser_advance(p)
		rhs := parser_parse_expr_bp(p, 7)
		e := new(Expr_PrefixOp)
		e^ = Expr_PrefixOp{op = tok.kind, operand = rhs, span = tok.span}
		return e

	case:
		collector_add_diag(p.collector, diag_unexpected_token(tok))
		parser_advance(p)
		e := new(Expr_Int)
		e^ = Expr_Int{value = 0, span = tok.span}
		return e
	}
}

parser_parse_tag_or_call :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	name_tok := parser_advance(p)
	name_id := intern(p.intern, name_tok.text)

	tag := new(Expr_Tag)
	tag^ = Expr_Tag{name = name_id, payload = make([dynamic]Expr, 0, 2), span = start}

	if p.current.kind == .LParen {
		parser_advance(p)
		for p.current.kind != .RParen && p.current.kind != .Eof {
			arg := parser_parse_expr(p)
			append(&tag.payload, arg)
			if p.current.kind == .Comma {
				parser_advance(p)
			}
		}
		parser_expect(p, .RParen)
	}

	if p.current.kind == .Dot {
		return parser_parse_method_chain(p, tag)
	}

	return tag
}

parser_parse_identifier_expr :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	name_tok := parser_advance(p)
	name_id := intern(p.intern, name_tok.text)

	if p.current.kind == .LParen {
		parser_advance(p)
		call := new(Expr_Call)
		call^ = Expr_Call{args = make([dynamic]Expr, 0, 4), span = start}
		id_expr := new(Expr_Identifier)
		id_expr^ = Expr_Identifier{name = name_id, span = name_tok.span}
		call.callee = id_expr

		for p.current.kind != .RParen && p.current.kind != .Eof {
			arg := parser_parse_expr(p)
			append(&call.args, arg)
			if p.current.kind == .Comma {
				parser_advance(p)
			}
		}
		parser_expect(p, .RParen)

		if p.current.kind == .Dot {
			return parser_parse_method_chain(p, call)
		}

		return call
	}

	if p.current.kind == .Dot {
		id_expr := new(Expr_Identifier)
		id_expr^ = Expr_Identifier{name = name_id, span = name_tok.span}
		return parser_parse_method_chain(p, id_expr)
	}

	e := new(Expr_Identifier)
	e^ = Expr_Identifier{name = name_id, span = name_tok.span}
	return e
}

parser_parse_method_chain :: proc(p: ^Parser, initial: Expr) -> Expr {
	result := initial
	for p.current.kind == .Dot {
		parser_advance(p)
		method_tok := parser_expect(p, .Identifier)
		method_id := intern(p.intern, method_tok.text)

		mc := new(Expr_Method_Call)
		mc^ = Expr_Method_Call{
			receiver = result,
			method = method_id,
			args = make([dynamic]Expr, 0, 4),
			span = method_tok.span,
		}

		if p.current.kind == .LParen {
			parser_advance(p)
			for p.current.kind != .RParen && p.current.kind != .Eof {
				arg := parser_parse_expr(p)
				append(&mc.args, arg)
				if p.current.kind == .Comma {
					parser_advance(p)
				}
			}
			parser_expect(p, .RParen)
		}

		result = mc
	}
	return result
}

parser_parse_lambda :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	parser_advance(p)

	type_params := make([dynamic]Intern_ID, 0, 4)
	params := make([dynamic]Func_Param, 0, 4)

	for p.current.kind != .Pipe && p.current.kind != .Eof {
		param := Func_Param{span = p.current.span}
		if p.current.kind == .Dot_Dot {
			parser_advance(p)
			if p.current.kind == .Comma {
				parser_advance(p)
			}
			continue
		}

		if p.current.kind == .Identifier || p.current.kind == .Upper_Id {
			name_tok := parser_advance(p)
			param.name = intern(p.intern, name_tok.text)
			if p.current.kind == .Colon {
				parser_advance(p)
				param.type_ann = parser_parse_type(p)
			}
		} else {
			collector_add_diag(p.collector, diag_expected_token(.Identifier, p.current, p.current.span))
			parser_advance(p)
		}
		append(&params, param)
		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .Pipe)

	return_type: ^Type = nil
	effects: ^Type = nil
	if p.current.kind == .Arrow {
		parser_advance(p)
		if p.current.kind == .LBrace {
			effects = parser_parse_effect_row_type(p)
		}
		return_type = parser_parse_type(p)
	}

	body := parser_parse_expr(p)

	e := new(Expr_Lambda)
	e^ = Expr_Lambda{
		type_params = type_params,
		params = params,
		return_type = return_type,
		effects = effects,
		body = body,
		span = start,
	}
	return e
}

parser_parse_block_or_record :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	parser_advance(p)

	if p.current.kind == .Dot_Dot {
		return parser_parse_record_expr(p, start)
	}

	if p.current.kind == .Identifier || p.current.kind == .Upper_Id {
		saved_pos := p.lexer.pos
		saved_tok := p.current
		next := lexer_next(p.lexer)
		is_record := next.kind == .Colon

		p.lexer.pos = saved_pos
		p.current = saved_tok

		if is_record {
			return parser_parse_record_expr(p, start)
		}
	}

	return parser_parse_block(p, start)
}

parser_parse_block :: proc(p: ^Parser, start: Source_Span) -> Expr {
	stmts := make([dynamic]Expr, 0, 8)

	for p.current.kind != .RBrace && p.current.kind != .Eof {
		stmt := parser_parse_expr_or_decl(p)
		append(&stmts, stmt)
	}
	parser_expect(p, .RBrace)

	e := new(Expr_Block)
	e^ = Expr_Block{statements = stmts, span = start}
	return e
}

	parser_parse_expr_or_decl :: proc(p: ^Parser) -> Expr {
	if p.current.kind == .Kw_Expect {
		parser_advance(p)
		cond := parser_parse_expr(p)
		e := new(Expr_Call)
		id := new(Expr_Identifier)
		id^ = Expr_Identifier{name = intern(p.intern, "expect"), span = p.current.span}
		args := make([dynamic]Expr, 0, 4)
		append(&args, cond)
		e^ = Expr_Call{callee = id, args = args, span = p.current.span}
		return e
	}

	if p.current.kind == .Dollar {
		start := p.current.span
		parser_advance(p)
		name_tok := parser_expect(p, .Identifier)
		name_id := intern(p.intern, name_tok.text)

		type_ann: ^Type = nil
		if p.current.kind == .Colon {
			parser_advance(p)
			type_ann = parser_parse_type(p)
		}

		parser_expect(p, .Eq)
		value := parser_parse_expr(p)

		id_expr := new(Expr_Dollar_Identifier)
		id_expr^ = Expr_Dollar_Identifier{name = name_id, span = start}
		assign := new(Expr_Assign)
		assign^ = Expr_Assign{target = id_expr, value = value, span = start}
		return assign
	}

	expr := parser_parse_expr(p)
	if p.current.kind == .Eq {
		parser_advance(p)
		value := parser_parse_expr(p)
		assign := new(Expr_Assign)
		assign^ = Expr_Assign{target = expr, value = value, span = p.current.span}
		return assign
	}
	return expr
}

parser_parse_record_expr :: proc(p: ^Parser, start: Source_Span) -> Expr {
	fields := make([dynamic]Record_Field, 0, 8)
	rest_expr: Expr = nil
	is_open := false

	if p.current.kind == .Dot_Dot {
		parser_advance(p)
		rest_expr = parser_parse_expr(p)
		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}

	for p.current.kind != .RBrace && p.current.kind != .Eof {
		if p.current.kind == .Dot_Dot {
			is_open = true
			parser_advance(p)
			if p.current.kind == .Identifier {
				parser_advance(p)
			}
			if p.current.kind == .Comma {
				parser_advance(p)
			}
			continue
		}

		name_tok := parser_expect(p, .Identifier)
		name_id := intern(p.intern, name_tok.text)

		value: Expr = nil
		if p.current.kind == .Colon {
			parser_advance(p)
			value = parser_parse_expr(p)
		} else {
			id_expr := new(Expr_Identifier)
			id_expr^ = Expr_Identifier{name = name_id, span = name_tok.span}
			value = id_expr
		}

		append(&fields, Record_Field{name = name_id, value = value, span = name_tok.span})

		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	e := new(Expr_Record)
	e^ = Expr_Record{fields = fields, rest = rest_expr, is_open = is_open, span = start}
	return e
}

parser_parse_list :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	parser_advance(p)

	elements := make([dynamic]Expr, 0, 8)

	for p.current.kind != .RBrack && p.current.kind != .Eof {
		elem := parser_parse_expr(p)
		append(&elements, elem)
		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrack)

	e := new(Expr_List)
	e^ = Expr_List{elements = elements, span = start}
	return e
}

parser_parse_if :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	parser_advance(p)

	condition := parser_parse_expr(p)
	then_branch := parser_parse_expr(p)

	else_branch: Expr = nil
	if p.current.kind == .Kw_Else {
		parser_advance(p)
		else_branch = parser_parse_expr(p)
	}

	e := new(Expr_If)
	e^ = Expr_If{condition = condition, then_branch = then_branch, else_branch = else_branch, span = start}
	return e
}

parser_parse_match :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	parser_advance(p)

	scrutinee := parser_parse_expr(p)

	arms := make([dynamic]Match_Arm, 0, 8)

	parser_expect(p, .LBrace)
	for p.current.kind != .RBrace && p.current.kind != .Eof {
		pattern := parser_parse_pattern(p)
		parser_expect(p, .Fat_Arrow)
		body := parser_parse_expr(p)
		append(&arms, Match_Arm{pattern = pattern, body = body, span = p.current.span})
		if p.current.kind == .Comma || p.current.kind == .Pipe {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	e := new(Expr_Match)
	e^ = Expr_Match{scrutinee = scrutinee, arms = arms, span = start}
	return e
}

parser_parse_handle :: proc(p: ^Parser) -> Expr {
	start := p.current.span
	is_shallow := p.current.kind == .Kw_Intercept
	parser_advance(p)

	effect_tok := parser_expect(p, .Upper_Id)
	effect_id := intern(p.intern, effect_tok.text)

	parser_expect(p, .Kw_In)
	body := parser_parse_expr(p)

	parser_expect(p, .Kw_With)
	parser_expect(p, .LBrace)

	arms := make([dynamic]Handler_Arm, 0, 8)
	for p.current.kind != .RBrace && p.current.kind != .Eof {
		parser_expect(p, .Dot)
		op_tok := parser_expect(p, .Identifier)
		op_id := intern(p.intern, op_tok.text)
		parser_expect(p, .Bang)
		parser_expect(p, .LParen)
		resume_tok := parser_expect(p, .Identifier)
		resume_id := intern(p.intern, resume_tok.text)
		parser_expect(p, .RParen)
		parser_expect(p, .Fat_Arrow)
		arm_body := parser_parse_expr(p)
		append(&arms, Handler_Arm{op = op_id, resume_id = resume_id, body = arm_body, span = op_tok.span})
		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	e := new(Expr_Handle)
	e^ = Expr_Handle{effect = effect_id, is_shallow = is_shallow, body = body, arms = arms, span = start}
	return e
}

parser_parse_pattern :: proc(p: ^Parser) -> Pattern {
	#partial switch p.current.kind {
	case .Upper_Id:
		name_tok := parser_advance(p)
		name_id := intern(p.intern, name_tok.text)

		pat := new(Pattern_Tag)
		pat^ = Pattern_Tag{name = name_id, payload = make([dynamic]Pattern, 0, 2), span = name_tok.span}

		if p.current.kind == .LParen {
			parser_advance(p)
			for p.current.kind != .RParen && p.current.kind != .Eof {
				inner := parser_parse_pattern(p)
				append(&pat.payload, inner)
				if p.current.kind == .Comma {
					parser_advance(p)
				}
			}
			parser_expect(p, .RParen)
		}
		return pat

	case .Identifier:
		name_tok := parser_advance(p)
		name_id := intern(p.intern, name_tok.text)
		pat := new(Pattern_Identifier)
		pat^ = Pattern_Identifier{name = name_id, span = name_tok.span}
		return pat

	case .Int_Literal:
		tok := parser_advance(p)
		pat := new(Pattern_Int)
		pat^ = Pattern_Int{value = tok.int_value, span = tok.span}
		return pat

	case .String_Literal:
		tok := parser_advance(p)
		pat := new(Pattern_String)
		pat^ = Pattern_String{value = tok.text, span = tok.span}
		return pat

	case .Kw_True, .Kw_False:
		tok := parser_advance(p)
		pat := new(Pattern_Bool)
		pat^ = Pattern_Bool{value = tok.kind == .Kw_True, span = tok.span}
		return pat

	case .LBrace:
		return parser_parse_record_pattern(p)

	case .LBrack:
		return parser_parse_list_pattern(p)

	case:
		tok := parser_advance(p)
		pat := new(Pattern_Wildcard)
		pat^ = Pattern_Wildcard{span = tok.span}
		return pat
	}
}

parser_parse_record_pattern :: proc(p: ^Parser) -> Pattern {
	start := p.current.span
	parser_advance(p)

	fields := make([dynamic]Pattern_Field, 0, 8)
	is_open := false

	for p.current.kind != .RBrace && p.current.kind != .Eof {
		if p.current.kind == .Dot_Dot {
			is_open = true
			parser_advance(p)
			if p.current.kind == .Comma {
				parser_advance(p)
			}
			continue
		}

		name_tok := parser_expect(p, .Identifier)
		name_id := intern(p.intern, name_tok.text)

		binding: Intern_ID = name_id
		if p.current.kind == .Colon {
			parser_advance(p)
			binding_tok := parser_expect(p, .Identifier)
			binding = intern(p.intern, binding_tok.text)
		}

		append(&fields, Pattern_Field{name = name_id, binding = binding, span = name_tok.span})

		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	pat := new(Pattern_Record)
	pat^ = Pattern_Record{fields = fields, is_open = is_open, span = start}
	return pat
}

parser_parse_list_pattern :: proc(p: ^Parser) -> Pattern {
	start := p.current.span
	parser_advance(p)

	elements := make([dynamic]Pattern, 0, 8)

	for p.current.kind != .RBrack && p.current.kind != .Eof {
		elem := parser_parse_pattern(p)
		append(&elements, elem)
		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrack)

	pat := new(Pattern_List)
	pat^ = Pattern_List{elements = elements, span = start}
	return pat
}

parser_parse_type :: proc(p: ^Parser) -> ^Type {
	t: Type = nil

	#partial switch p.current.kind {
	case .Upper_Id:
		name_tok := parser_advance(p)
		name_id := intern(p.intern, name_tok.text)

		if p.current.kind == .LParen {
			parser_advance(p)
			applied := new(Type_Applied)
			applied^ = Type_Applied{name = name_id, args = make([dynamic]Type, 0, 4), span = name_tok.span}
			for p.current.kind != .RParen && p.current.kind != .Eof {
				arg := parser_parse_type(p)
				append(&applied.args, arg^)
				if p.current.kind == .Comma {
					parser_advance(p)
				}
			}
			parser_expect(p, .RParen)
			t = applied
		} else {
			prim := new(Type_Primitive)
			prim^ = Type_Primitive{name = name_id, span = name_tok.span}
			t = prim
		}

	case .Identifier:
		name_tok := parser_advance(p)
		name_id := intern(p.intern, name_tok.text)
		v := new(Type_Variable)
		v^ = Type_Variable{name = name_id, span = name_tok.span}
		t = v

	case .LBrace:
		t = parser_parse_record_type(p)

	case .LBrack:
		t = parser_parse_tag_union_type(p)

	case .LParen, .Pipe:
		t = parser_parse_function_type(p)

	case:
		collector_add_diag(p.collector, diag_expected_type(p.current, p.current.span))
		parser_advance(p)
		v := new(Type_Variable)
		v^ = Type_Variable{name = intern(p.intern, "_"), span = p.current.span}
		t = v
	}

	result := new(Type)
	result^ = t
	return result
}

parser_parse_function_type :: proc(p: ^Parser) -> Type {
	start := p.current.span
	params := make([dynamic]Type, 0, 4)

	if p.current.kind == .LParen {
		parser_advance(p)
		for p.current.kind != .RParen && p.current.kind != .Eof {
			param := parser_parse_type(p)
			append(&params, param^)
			if p.current.kind == .Comma {
				parser_advance(p)
			}
		}
		parser_expect(p, .RParen)
	} else {
		parser_expect(p, .Pipe)
		parser_expect(p, .Pipe)
	}

	effects: ^Type = nil
	if p.current.kind == .Arrow {
		parser_advance(p)
		if p.current.kind == .LBrace {
			effects = parser_parse_effect_row_type(p)
		}
		return_type := parser_parse_type(p)
		ft := new(Type_Function)
		ft^ = Type_Function{params = params, effects = effects, return_ = return_type^, span = start}
		return ft
	}

	return nil
}

parser_parse_record_type :: proc(p: ^Parser) -> Type {
	start := p.current.span
	parser_advance(p)

	fields := make([dynamic]Type_Field, 0, 8)
	rest: Intern_ID = 0
	is_open := false

	for p.current.kind != .RBrace && p.current.kind != .Eof {
		if p.current.kind == .Dot_Dot {
			is_open = true
			parser_advance(p)
			if p.current.kind == .Identifier {
				rest_tok := parser_advance(p)
				rest = intern(p.intern, rest_tok.text)
			}
			if p.current.kind == .Comma {
				parser_advance(p)
			}
			continue
		}

		name_tok := parser_expect(p, .Identifier)
		name_id := intern(p.intern, name_tok.text)
		parser_expect(p, .Colon)
		field_type := parser_parse_type(p)

		append(&fields, Type_Field{name = name_id, type = field_type^, span = name_tok.span})

		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	rec := new(Type_Record)
	rec^ = Type_Record{fields = fields, rest = rest, is_open = is_open, span = start}
	return rec
}

parser_parse_tag_union_type :: proc(p: ^Parser) -> Type {
	start := p.current.span
	parser_advance(p)

	tags := make([dynamic]Type_Tag, 0, 8)
	rest: Intern_ID = 0
	is_open := false

	for p.current.kind != .RBrack && p.current.kind != .Eof {
		if p.current.kind == .Dot_Dot {
			is_open = true
			parser_advance(p)
			if p.current.kind == .Identifier {
				rest_tok := parser_advance(p)
				rest = intern(p.intern, rest_tok.text)
			}
			if p.current.kind == .Pipe {
				parser_advance(p)
			}
			continue
		}

		name_tok := parser_expect(p, .Upper_Id)
		name_id := intern(p.intern, name_tok.text)

		payload := make([dynamic]Type, 0, 2)

		if p.current.kind == .LParen {
			parser_advance(p)
			for p.current.kind != .RParen && p.current.kind != .Eof {
				arg := parser_parse_type(p)
				append(&payload, arg^)
				if p.current.kind == .Comma {
					parser_advance(p)
				}
			}
			parser_expect(p, .RParen)
		}

		append(&tags, Type_Tag{name = name_id, payload = payload, span = name_tok.span})

		if p.current.kind == .Pipe {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrack)

	tag_union := new(Type_Tag_Union)
	tag_union^ = Type_Tag_Union{tags = tags, rest = rest, is_open = is_open, span = start}
	return tag_union
}

parser_parse_effect_row_type :: proc(p: ^Parser) -> ^Type {
	start := p.current.span
	parser_advance(p)

	effects := make([dynamic]Intern_ID, 0, 8)
	rest: Intern_ID = 0
	is_open := false

	for p.current.kind != .RBrace && p.current.kind != .Eof {
		if p.current.kind == .Dot_Dot {
			is_open = true
			parser_advance(p)
			if p.current.kind == .Identifier {
				rest_tok := parser_advance(p)
				rest = intern(p.intern, rest_tok.text)
			}
			if p.current.kind == .Comma {
				parser_advance(p)
			}
			continue
		}

		name_tok := parser_expect(p, .Upper_Id)
		name_id := intern(p.intern, name_tok.text)
		append(&effects, name_id)

		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	row := new(Type_Effect_Row)
	row^ = Type_Effect_Row{effects = effects, rest = rest, is_open = is_open, span = start}
	result := new(Type)
	result^ = row
	return result
}

parser_parse_effect_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
	start := p.current.span
	parser_advance(p)

	name_tok := parser_expect(p, .Upper_Id)
	name_id := intern(p.intern, name_tok.text)

	ops := make([dynamic]Effect_Op, 0, 8)

	parser_expect(p, .LBrace)
	for p.current.kind != .RBrace && p.current.kind != .Eof {
		op_name_tok := parser_advance(p)
		op_name_text := op_name_tok.text
		is_effectful := p.current.kind == .Bang
		if is_effectful {
			parser_advance(p)
			op_name_text = strings.concatenate({op_name_tok.text, "!"}, context.allocator)
		}
		op_name_id := intern(p.intern, op_name_text)

		parser_expect(p, .Colon)
		return_type := parser_parse_type(p)

		append(&ops, Effect_Op{name = op_name_id, is_effectful = is_effectful, return_type = return_type, span = op_name_tok.span})

		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	decl := new(Decl_Effect)
	decl^ = Decl_Effect{name = name_id, is_pub = is_pub, operations = ops, span = start}
	return decl
}

parser_parse_trait_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
	start := p.current.span
	parser_advance(p)

	name_tok := parser_expect(p, .Upper_Id)
	name_id := intern(p.intern, name_tok.text)

	parent: Intern_ID = 0
	if p.current.kind == .Kw_Is {
		parser_advance(p)
		parent_tok := parser_expect(p, .Upper_Id)
		parent = intern(p.intern, parent_tok.text)
	}

	methods := make([dynamic]Trait_Method, 0, 8)

	parser_expect(p, .LBrace)
	for p.current.kind != .RBrace && p.current.kind != .Eof {
		m_name_tok := parser_advance(p)
		m_name_id := intern(p.intern, m_name_tok.text)

		parser_expect(p, .Colon)
		return_type := parser_parse_type(p)

		append(&methods, Trait_Method{name = m_name_id, return_type = return_type, span = m_name_tok.span})

		if p.current.kind == .Comma {
			parser_advance(p)
		}
	}
	parser_expect(p, .RBrace)

	decl := new(Decl_Trait)
	decl^ = Decl_Trait{name = name_id, is_pub = is_pub, parent = parent, methods = methods, span = start}
	return decl
}

parser_parse_alias_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
	start := p.current.span
	parser_advance(p)

	name_tok := parser_expect(p, .Upper_Id)
	name_id := intern(p.intern, name_tok.text)
	parser_expect(p, .Eq)
	target := parser_parse_type(p)

	decl := new(Decl_Alias)
	decl^ = Decl_Alias{name = name_id, is_pub = is_pub, target = target, span = start}
	return decl
}

parser_parse_import_decl :: proc(p: ^Parser, is_pub: bool) -> Decl {
	start := p.current.span

	is_unsafe := false
	if p.current.kind == .Kw_Unsafe {
		parser_advance(p)
		is_unsafe = true
	}

	parser_advance(p)

	module_tok := parser_expect(p, .Upper_Id)
	module_name := module_tok.text

	exposing := make([dynamic]Intern_ID, 0, 8)

	alias: Intern_ID = 0

	if p.current.kind == .Kw_Exposing {
		parser_advance(p)
		parser_expect(p, .LBrack)
		for p.current.kind != .RBrack && p.current.kind != .Eof {
			name_tok := parser_advance(p)
			append(&exposing, intern(p.intern, name_tok.text))
			if p.current.kind == .Comma {
				parser_advance(p)
			}
		}
		parser_expect(p, .RBrack)
	}

	if p.current.kind == .Kw_As {
		parser_advance(p)
		alias_tok := parser_expect(p, .Upper_Id)
		alias = intern(p.intern, alias_tok.text)
	}

	decl := new(Decl_Import)
	decl^ = Decl_Import{module = module_name, exposing = exposing, alias = alias, is_unsafe = is_unsafe, span = start}
	return decl
}

parser_parse_test_decl :: proc(p: ^Parser) -> Decl {
	start := p.current.span
	parser_advance(p)

	name_tok := parser_expect(p, .String_Literal)
	parser_expect(p, .Eq)

	body := parser_parse_expr(p)

	decl := new(Decl_Test)
	decl^ = Decl_Test{name = name_tok.text, body = body, span = start}
	return decl
}

parser_parse_expect_decl :: proc(p: ^Parser) -> Decl {
	start := p.current.span
	parser_advance(p)

	condition := parser_parse_expr(p)

	decl := new(Decl_Expect)
	decl^ = Decl_Expect{condition = condition, span = start}
	return decl
}
