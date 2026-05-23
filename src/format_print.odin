package camp

import "core:strings"

Doc_Mode :: enum {
	Flat,
	Broken,
}

doc_resolve :: proc(d: Doc, indent: int) -> string {
	return doc_resolve_inner(d, indent, .Broken)
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

doc_resolve_inner :: proc(d: Doc, indent: int, mode: Doc_Mode) -> string {
	switch d.kind {
	case .Empty:
		return ""
	case .Text:
		return d.text
	case .Line:
		return doc_newline_with_indent(indent)
	case .Soft_Line:
		if mode == .Flat {
			return " "
		}
		return doc_newline_with_indent(indent)
	case .Backslash_Break:
		return doc_newline_with_indent(indent)
	case .Nest:
		if len(d.children) > 0 {
			return doc_resolve_inner(d.children[0], indent + d.indent, mode)
		}
		return ""
	case .Align:
		if len(d.children) > 0 {
			return doc_resolve_inner(d.children[0], indent, mode)
		}
		return ""
	case .Group:
		if doc_has_hard_break(d) {
			return doc_resolve_children(d.children, indent, .Broken)
		}
		return doc_resolve_children(d.children, indent, .Flat)
	case .Concat:
		return doc_resolve_children(d.children, indent, mode)
	}
	return ""
}

doc_resolve_children :: proc(children: [dynamic]Doc, indent: int, mode: Doc_Mode) -> string {
	b: strings.Builder
	strings.builder_init_none(&b, context.allocator)
	defer strings.builder_destroy(&b)
	for child in children {
		strings.write_string(&b, doc_resolve_inner(child, indent, mode))
	}
	return strings.clone(strings.to_string(b))
}

doc_newline_with_indent :: proc(indent: int) -> string {
	b: strings.Builder
	strings.builder_init_none(&b, context.allocator)
	defer strings.builder_destroy(&b)
	strings.write_byte(&b, '\n')
	for _ in 0 ..< indent {
		strings.write_byte(&b, ' ')
	}
	return strings.clone(strings.to_string(b))
}
