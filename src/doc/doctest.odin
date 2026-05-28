package doc

import "core:fmt"
import "core:strings"

import "camp:base"
import "camp:frontend"

Doc_Test :: struct {
	name:        string,
	code:        string,
	decl_name:   string,
	decl_path:   string,
	doc_comment: string,
	line_number: int,
}

extract_doc_tests :: proc(
	doc: string,
	decl_name: string,
	decl_path: string,
	source_offset: int,
) -> [dynamic]Doc_Test {
	tests: [dynamic]Doc_Test
	tests.allocator = context.allocator

	lines := strings.split(doc, "\n", context.allocator)
	defer delete(lines, context.allocator)

	current_block: [dynamic]string
	in_code_block := false
	code_block_start_line := 0
	block_label := ""

	for i in 0 ..< len(lines) {
		line := lines[i]
		is_hidden := strings.has_prefix(strings.trim_space(line), "//#")
		trimmed := strings.trim_space(line)

		if strings.has_prefix(trimmed, "```") {
			if !in_code_block {
				in_code_block = true
				code_block_start_line = i
				block_label = len(trimmed) == 3 ? "" : strings.trim_space(trimmed[3:])
				current_block = make([dynamic]string, 0, 8)
			} else {
				code := join_code_lines(current_block[:])
				if code != "" {
					label := block_label != "" ? block_label : fmt.tprintf("{}", code_block_start_line + source_offset + 1)
					append(&tests, Doc_Test{
						name        = label,
						code        = code,
						decl_name   = decl_name,
						decl_path   = decl_path,
						doc_comment = "",
						line_number = code_block_start_line + source_offset + 1,
					})
				}
				delete(current_block)
				current_block = make([dynamic]string, 0, 8)
				in_code_block = false
				block_label = ""
			}
			continue
		}

		if in_code_block && !is_hidden {
			append(&current_block, line)
		}
	}

	if in_code_block && len(current_block) > 0 {
		code := join_code_lines(current_block[:])
		if code != "" {
			label := block_label != "" ? block_label : fmt.tprintf("{}", code_block_start_line + source_offset + 1)
			append(&tests, Doc_Test{
				name        = label,
				code        = code,
				decl_name   = decl_name,
				decl_path   = decl_path,
				doc_comment = "",
				line_number = code_block_start_line + source_offset + 1,
			})
		}
		delete(current_block)
	}

	return tests
}

join_code_lines :: proc(lines: []string) -> string {
	if len(lines) == 0 {
		return ""
	}
	b := strings.builder_make(context.allocator)
	first := true
	for line in lines {
		if !first {
			strings.write_byte(&b, '\n')
		}
		first = false
		strings.write_string(&b, line)
	}
	return strings.to_string(b)
}

extract_all_doc_tests :: proc(
	ast_file: ^frontend.File,
	interner: ^base.Intern_Table,
	source: string,
	file_path: string,
) -> [dynamic]Doc_Test {
	tests: [dynamic]Doc_Test
	tests.allocator = context.allocator

	for decl in ast_file.decls {
		decl_name := ""
		doc_text := ""
		line_offset := 0

		#partial switch d in decl {
		case ^frontend.Decl_Const:
			if d.doc_comment == "" do continue
			decl_name = base.intern_get(interner, d.name)
			doc_text = d.doc_comment
			line_offset = _calc_doc_line_offset(source, d.span.start)
		case ^frontend.Decl_Effect:
			if d.doc_comment == "" do continue
			decl_name = base.intern_get(interner, d.name)
			doc_text = d.doc_comment
			line_offset = _calc_doc_line_offset(source, d.span.start)
		case ^frontend.Decl_Trait:
			if d.doc_comment == "" do continue
			decl_name = base.intern_get(interner, d.name)
			doc_text = d.doc_comment
			line_offset = _calc_doc_line_offset(source, d.span.start)
		case ^frontend.Decl_Alias:
			if d.doc_comment == "" do continue
			decl_name = base.intern_get(interner, d.name)
			doc_text = d.doc_comment
			line_offset = _calc_doc_line_offset(source, d.span.start)
		case ^frontend.Decl_Newtype:
			if d.doc_comment == "" do continue
			decl_name = base.intern_get(interner, d.name)
			doc_text = d.doc_comment
			line_offset = _calc_doc_line_offset(source, d.span.start)
		case ^frontend.Decl_Test:
			if d.doc_comment == "" do continue
			decl_name = d.name
			doc_text = d.doc_comment
			line_offset = _calc_doc_line_offset(source, d.span.start)
		case:
			continue
		}

		if decl_name == "" || doc_text == "" do continue

		extracted := extract_doc_tests(doc_text, decl_name, file_path, line_offset)
		for t in extracted {
			append(&tests, t)
		}
	}

	return tests
}

_calc_doc_line_offset :: proc(source: string, decl_byte_offset: int) -> int {
	line_offset := 0
	for i := 0; i < decl_byte_offset && i < len(source); i += 1 {
		if source[i] == '\n' {
			line_offset += 1
		}
	}
	return line_offset
}