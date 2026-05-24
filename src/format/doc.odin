package format

import "core:strings"

Doc_Kind :: enum {
	Empty,
	Text,
	Line,
	Soft_Line,
	Nest,
	Group,
	Concat,
	Align,
	Backslash_Break,
}

Doc :: struct {
	kind:     Doc_Kind,
	text:     string,
	indent:   int,
	children: [dynamic]Doc,
}

doc_empty :: proc() -> Doc {
	return Doc{kind = .Empty}
}

doc_text :: proc(text: string) -> Doc {
	return Doc{kind = .Text, text = text}
}

doc_line :: proc() -> Doc {
	return Doc{kind = .Line}
}

doc_soft_line :: proc() -> Doc {
	return Doc{kind = .Soft_Line}
}

doc_nest :: proc(indent: int, d: Doc) -> Doc {
	children := make([dynamic]Doc, 1)
	children[0] = d
	return Doc{kind = .Nest, indent = indent, children = children}
}

doc_group :: proc(children: []Doc) -> Doc {
	dyn := make([dynamic]Doc, len(children))
	for child, i in children {
		dyn[i] = child
	}
	return Doc{kind = .Group, children = dyn}
}

doc_concat :: proc(children: []Doc) -> Doc {
	dyn := make([dynamic]Doc, len(children))
	for child, i in children {
		dyn[i] = child
	}
	return Doc{kind = .Concat, children = dyn}
}

doc_backslash_break :: proc() -> Doc {
	return Doc{kind = .Backslash_Break}
}

doc_space :: proc() -> Doc {
	return doc_text(" ")
}

doc_destroy :: proc(d: Doc) {
	if len(d.children) > 0 {
		for child in d.children {
			doc_destroy(child)
		}
		delete(d.children)
	}
}
