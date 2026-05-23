package camp

import "core:strings"

Comment_Info :: struct {
	text:   string,
	span:   Source_Span,
	is_doc: bool,
}

Format_Source_Info :: struct {
	source:                string,
	blank_line_after:      map[int]bool,
	comments_before:       map[int][]Comment_Info,
	trailing_comments:     map[int]Comment_Info,
	has_backslash:         map[int]bool,
	first_separator_break: map[int]bool,
}

is_separator :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .Comma, .Pipe:
		return true
	case .Plus, .Minus, .Star, .Slash, .Percent:
		return true
	case .Amp, .Caret, .Tilde:
		return true
	case .Fat_Arrow, .Arrow:
		return true
	case .Eq_Eq, .Bang_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:
		return true
	}
	return false
}

is_open_delim :: proc(kind: Token_Kind) -> bool {
	return kind == .LParen || kind == .LBrack || kind == .LBrace
}

is_close_delim :: proc(kind: Token_Kind) -> bool {
	return kind == .RParen || kind == .RBrack || kind == .RBrace
}

analyze_source :: proc(source: string, tokens: []Token) -> Format_Source_Info {
	info: Format_Source_Info
	info.source = source
	info.first_separator_break = make(map[int]bool)
	info.blank_line_after = make(map[int]bool)
	info.comments_before = make(map[int][]Comment_Info)
	info.trailing_comments = make(map[int]Comment_Info)
	info.has_backslash = make(map[int]bool)

	if len(tokens) == 0 {
		return info
	}

	separator_analysis(source, tokens, &info)
	source_text_analysis(source, tokens, &info)

	return info
}

separator_analysis :: proc(source: string, tokens: []Token, info: ^Format_Source_Info) {
	depth := 0
	first_sep_at_depth: map[int]bool
	defer delete(first_sep_at_depth)
	open_delim_pos: map[int]int
	defer delete(open_delim_pos)

	for token, i in tokens {
		if token.kind == .Eof {
			break
		}

		if is_open_delim(token.kind) {
			depth += 1
			first_sep_at_depth[depth] = false
			open_delim_pos[depth] = token.span.start
		} else if is_close_delim(token.kind) {
			depth -= 1
		}

		if depth > 0 && is_separator(token.kind) {
			if !first_sep_at_depth[depth] {
				first_sep_at_depth[depth] = true

				if i + 1 < len(tokens) {
					next := tokens[i + 1]
					if next.kind != .Eof {
						gap := source[token.span.end:next.span.start]
						has_break := strings.contains(gap, "\n")
						if pos, ok := open_delim_pos[depth]; ok {
							info.first_separator_break[pos] = has_break
						}
					}
				}
			}
		}
	}
}

Comment_Found :: struct {
	text:   string,
	start:  int,
	end:    int,
	line:   int,
	is_doc: bool,
}

collect_comments :: proc(source: string) -> [dynamic]Comment_Found {
	comments: [dynamic]Comment_Found

	i := 0
	current_line := 1
	for i < len(source) {
		if source[i] == '\n' {
			current_line += 1
			i += 1
			continue
		}

		if i + 1 < len(source) && source[i] == '-' && source[i + 1] == '-' {
			start := i
			i += 2

			is_doc := false
			if i < len(source) && source[i] == '-' {
				is_doc = true
				i += 1
			}

			comment_start := i
			for i < len(source) && source[i] != '\n' {
				i += 1
			}
			comment_text := strings.trim_space(source[comment_start:i])
			comment_end := i

			append(&comments, Comment_Found{
				text = comment_text,
				start = start,
				end = comment_end,
				line = current_line,
				is_doc = is_doc,
			})
		} else {
			i += 1
		}
	}

	return comments
}

token_line :: proc(source: string, pos: int) -> int {
	line := 1
	for i := 0; i < pos && i < len(source); i += 1 {
		if source[i] == '\n' {
			line += 1
		}
	}
	return line
}

source_text_analysis :: proc(source: string, tokens: []Token, info: ^Format_Source_Info) {
	comments := collect_comments(source)
	defer delete(comments)

	// Build a map from token start position to line number
	token_start_to_line := make(map[int]int)
	defer delete(token_start_to_line)
	for tok in tokens {
		if tok.kind == .Eof do continue
		token_start_to_line[tok.span.start] = token_line(source, tok.span.start)
	}

	if len(comments) > 0 {
		for comment in comments {
			// Find the previous and next real tokens around this comment
			next_token_idx := -1
			prev_token_idx := -1
			for j := 0; j < len(tokens); j += 1 {
				if tokens[j].kind == .Eof do continue
				if tokens[j].span.start >= comment.start {
					next_token_idx = j
					break
				}
				prev_token_idx = j
			}

			if prev_token_idx >= 0 {
				prev := tokens[prev_token_idx]
				comment_line := comment.line
				prev_line := token_start_to_line[prev.span.start]

				if comment_line == prev_line {
					// Comment is on the same line as the previous token → trailing
					ci := Comment_Info{
						text = comment.text,
						span = Source_Span{start = comment.start, end = comment.end},
						is_doc = comment.is_doc,
					}
					info.trailing_comments[prev.span.start] = ci
				} else if next_token_idx >= 0 {
					// Comment is on its own line before the next token
					next := tokens[next_token_idx]
					if next.kind == .Eof do continue
					ci := Comment_Info{
						text = comment.text,
						span = Source_Span{start = comment.start, end = comment.end},
						is_doc = comment.is_doc,
					}
				existing := info.comments_before[next.span.start]
				new_slice := make([]Comment_Info, len(existing) + 1)
				copy(new_slice, existing)
				new_slice[len(existing)] = ci
				delete(existing)
				info.comments_before[next.span.start] = new_slice
			}
		} else if next_token_idx >= 0 {
			// No previous token → comment before the first token
			next := tokens[next_token_idx]
			if next.kind == .Eof do continue
			ci := Comment_Info{
				text = comment.text,
				span = Source_Span{start = comment.start, end = comment.end},
				is_doc = comment.is_doc,
			}
			existing := info.comments_before[next.span.start]
			new_slice := make([]Comment_Info, len(existing) + 1)
			copy(new_slice, existing)
			new_slice[len(existing)] = ci
			delete(existing)
			info.comments_before[next.span.start] = new_slice
			}
		}
	}

	// Find blank lines between adjacent tokens
	for i := 0; i < len(tokens) - 1; i += 1 {
		tok := tokens[i]
		next := tokens[i + 1]
		if tok.kind == .Eof || next.kind == .Eof do continue

		gap := source[tok.span.end:next.span.start]
		if has_blank_line_in_gap(gap) {
			info.blank_line_after[tok.span.start] = true
		}
	}
}

destroy_format_source_info :: proc(info: ^Format_Source_Info) {
	// Free slice values inside comments_before
	for _, comments in info.comments_before {
		delete(comments)
	}
	delete(info.comments_before)
	delete(info.trailing_comments)
	delete(info.first_separator_break)
	delete(info.blank_line_after)
	delete(info.has_backslash)
}

has_blank_line_in_gap :: proc(gap: string) -> bool {
	// A blank line means two consecutive newlines (with optional whitespace)
	for i := 0; i < len(gap) - 1; i += 1 {
		if gap[i] == '\n' {
			j := i + 1
			for j < len(gap) && (gap[j] == ' ' || gap[j] == '\t') {
				j += 1
			}
			if j < len(gap) && gap[j] == '\n' {
				return true
			}
		}
	}
	return false
}
