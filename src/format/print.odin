package format

import "core:strings"

Doc_Mode :: enum {
	Flat,
	Broken,
}

doc_resolve :: proc(d: Doc, indent: int) -> string {
	b: strings.Builder
	strings.builder_init_none(&b, context.allocator)
	defer strings.builder_destroy(&b)
	doc_resolve_into(d, indent, .Broken, &b)
	return strings.clone(strings.to_string(b))
}

doc_has_hard_break :: proc(d: Doc) -> bool {
	#partial switch d.kind {
	case .Empty, .Text, .Soft_Line:
		return false
	case .Line, .Backslash_Break:
		return true
	case .Nest, .Align, .Group, .Concat:
		for child in d.children {
			if doc_has_hard_break(child) {
				return true
			}
		}
		return false
	}
	return false
}

doc_resolve_into :: proc(d: Doc, indent: int, mode: Doc_Mode, b: ^strings.Builder) {
	switch d.kind {
	case .Empty:
		return
	case .Text:
		strings.write_string(b, d.text)
	case .Line:
		write_newline_with_indent(b, indent)
	case .Soft_Line:
		if mode == .Flat {
			strings.write_byte(b, ' ')
		} else {
			write_newline_with_indent(b, indent)
		}
	case .Backslash_Break:
		write_newline_with_indent(b, indent)
	case .Nest:
		if len(d.children) > 0 {
			doc_resolve_into(d.children[0], indent + d.indent, mode, b)
		}
	case .Align:
		if len(d.children) > 0 {
			doc_resolve_into(d.children[0], indent, mode, b)
		}
	case .Group:
		child_mode: Doc_Mode = .Flat
		if doc_has_hard_break(d) {
			child_mode = .Broken
		}
		for child in d.children {
			doc_resolve_into(child, indent, child_mode, b)
		}
	case .Concat:
		for child in d.children {
			doc_resolve_into(child, indent, mode, b)
		}
	}
}

write_newline_with_indent :: proc(b: ^strings.Builder, indent: int) {
	strings.write_byte(b, '\n')
	for _ in 0 ..< indent {
		strings.write_byte(b, ' ')
	}
}

