package diagnostics

import "camp:base"

token_kind_display :: proc(kind: base.Token_Kind) -> string {
	switch kind {
	case .Eof:
		return "end of file"
	case .Int_Literal:
		return "integer"
	case .Float_Literal:
		return "float"
	case .String_Literal:
		return "string"
	case .Interpolated_String_Literal:
		return "interpolated string"
	case .Char_Literal:
		return "char"
	case .Perline_String_Literal:
		return "per-line string"

	case .Identifier:
		return "identifier"
	case .Upper_Id:
		return "uppercase identifier"
	case .Kw_If:
		return "if"
	case .Kw_Else:
		return "else"
	case .Kw_Match:
		return "match"
	case .Kw_Is:
		return "is"
	case .Kw_Derives:
		return "derives"
	case .Kw_Handle:
		return "handle"

	case .Kw_In:
		return "in"
	case .Kw_With:
		return "with"
	case .Kw_Import:
		return "import"

	case .Kw_As:
		return "as"

	case .Kw_For:
		return "for"
	case .Kw_And:
		return "and"
	case .Kw_Or:
		return "or"
	case .Kw_Expect:
		return "expect"
	case .Kw_Test:
		return "test"
	case .Kw_Not:
		return "not"
	case .Kw_Pub:
		return "pub"
	case .Kw_Self:
		return "Self"
	case .Kw_Par:
		return "par"
	case .Kw_Where:
		return "where"
	case .Kw_Return:
		return "return"
	case .Kw_Crash:
		return "crash"
	case .Kw_Deps:         return "deps"

	case .Kw_Todo:
		return "todo"
	case .Pipe:
		return "|"
	case .Arrow:
		return "->"
	case .Fat_Arrow:
		return "=>"
	case .Eq:
		return "="
	case .Colon_Eq:
		return ":="
	case .Colon:
		return ":"
	case .Comma:
		return ","
	case .Dot:
		return "."
	case .Dot_Dot:
		return ".."

	case .Dollar:
		return "$"
	case .Hash:
		return "#"
	case .At:
		return "@"
	case .Lt:
		return "<"
	case .Gt:
		return ">"
	case .Lt_Eq:
		return "<="
	case .Gt_Eq:
		return ">="
	case .Eq_Eq:
		return "=="
	case .Bang_Eq:
		return "!="
	case .Plus:
		return "+"
	case .Minus:
		return "-"
	case .Star:
		return "*"
	case .Slash:
		return "/"
	case .Percent:
		return "%"
	case .Amp:
		return "&"
	case .Caret:
		return "^"
	case .Tilde:
		return "~"
	case .Backslash:
		return "\\"
	case .LParen:
		return "("
	case .RParen:
		return ")"
	case .LBrack:
		return "["
	case .RBrack:
		return "]"
	case .LBrace:
		return "{"
	case .RBrace:
		return "}"
	case .Newline:
		return "newline"
	case .Doc_Comment:
		return "///"
	case .Hidden_Line:
		return "//#"
	case:
		return "unknown token"
	}
}

