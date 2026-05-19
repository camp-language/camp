package camp

import "core:testing"
import "core:strings"

@(test)
test_doc_text :: proc(t: ^testing.T) {
	d := doc_text("let")
	testing.expect(t, d.kind == .Text)
	testing.expect(t, d.text == "let")
}

@(test)
test_doc_empty :: proc(t: ^testing.T) {
	d := doc_empty()
	testing.expect(t, d.kind == .Empty)
}

@(test)
test_doc_line :: proc(t: ^testing.T) {
	d := doc_line()
	testing.expect(t, d.kind == .Line)
}

@(test)
test_doc_soft_line :: proc(t: ^testing.T) {
	d := doc_soft_line()
	testing.expect(t, d.kind == .Soft_Line)
}

@(test)
test_doc_concat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_text("b")}
	d := doc_concat(children)
	testing.expect(t, d.kind == .Concat)
	testing.expect(t, len(d.children) == 2)
	testing.expect(t, d.children[0].text == "a")
	testing.expect(t, d.children[1].text == "b")
}

@(test)
test_doc_group :: proc(t: ^testing.T) {
	children := []Doc{doc_text("hello"), doc_text("world")}
	d := doc_group(children)
	testing.expect(t, d.kind == .Group)
	testing.expect(t, len(d.children) == 2)
}

@(test)
test_doc_nest :: proc(t: ^testing.T) {
	inner := doc_text("body")
	d := doc_nest(4, inner)
	testing.expect(t, d.kind == .Nest)
	testing.expect(t, d.indent == 4)
	testing.expect(t, len(d.children) == 1)
}

@(test)
test_doc_backslash_break :: proc(t: ^testing.T) {
	d := doc_backslash_break()
	testing.expect(t, d.kind == .Backslash_Break)
}

@(test)
test_doc_space :: proc(t: ^testing.T) {
	d := doc_space()
	testing.expect(t, d.kind == .Text)
	testing.expect(t, d.text == " ")
}

@(test)
test_resolve_text :: proc(t: ^testing.T) {
	result := doc_resolve(doc_text("hello"), 0)
	defer delete(result)
	testing.expect(t, result == "hello")
}

@(test)
test_resolve_empty :: proc(t: ^testing.T) {
	result := doc_resolve(doc_empty(), 0)
	defer delete(result)
	testing.expect(t, result == "")
}

@(test)
test_resolve_group_flat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_soft_line(), doc_text("b")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a b")
}

@(test)
test_resolve_group_broken :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_line(), doc_text("b")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb")
}

@(test)
test_resolve_nest_indent :: proc(t: ^testing.T) {
	inner_children := []Doc{doc_text("b"), doc_line(), doc_text("c")}
	inner := doc_group(inner_children)
	nested := doc_nest(4, inner)
	outer_children := []Doc{doc_text("a"), doc_line(), nested}
	d := doc_group(outer_children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb\n    c")
}

@(test)
test_resolve_soft_line_flat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("x"), doc_soft_line(), doc_text("y")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "x y")
}

@(test)
test_resolve_group_nested_break :: proc(t: ^testing.T) {
	inner_children := []Doc{doc_text("b"), doc_line(), doc_text("c")}
	inner := doc_group(inner_children)
	outer_children := []Doc{doc_text("a"), doc_soft_line(), inner, doc_soft_line(), doc_text("d")}
	d := doc_group(outer_children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb\nc\nd")
}

@(test)
test_resolve_nest_no_line :: proc(t: ^testing.T) {
	inner := doc_nest(4, doc_text("b"))
	children := []Doc{doc_text("a"), doc_soft_line(), inner}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a b")
}

@(test)
test_resolve_backslash_break :: proc(t: ^testing.T) {
	children := []Doc{doc_text("a"), doc_backslash_break(), doc_text("b")}
	d := doc_group(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "a\nb")
}

@(test)
test_resolve_concat :: proc(t: ^testing.T) {
	children := []Doc{doc_text("foo"), doc_text("bar")}
	d := doc_concat(children)
	result := doc_resolve(d, 0)
	defer delete(result)
	testing.expect(t, result == "foobar")
}
