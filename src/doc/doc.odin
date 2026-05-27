package doc

import "camp:base"
import "camp:semantics"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

generate :: proc(
	canon: semantics.CFile,
	store: ^semantics.Type_Store,
	interner: ^base.Intern_Table,
) {
	builder: strings.Builder
	strings.builder_init(&builder, context.allocator)
	defer strings.builder_destroy(&builder)

	fmt.sbprintf(&builder, "<!DOCTYPE html>\n")
	fmt.sbprintf(&builder, "<html lang=\"en\">\n")
	fmt.sbprintf(&builder, "<head>\n")
	fmt.sbprintf(&builder, "<meta charset=\"utf-8\">\n")
	fmt.sbprintf(&builder, "<title>{} - Camp Documentation</title>\n", canon.path)
	fmt.sbprintf(&builder, "<style>\n")
	fmt.sbprintf(
		&builder,
		"body {{ font-family: sans-serif; max-width: 800px; margin: 2em auto; padding: 0 1em; }}\n",
	)
	fmt.sbprintf(&builder, "pre {{ background: #f5f5f5; padding: 1em; overflow-x: auto; }}\n")
	fmt.sbprintf(&builder, "code {{ font-family: monospace; }}\n")
	fmt.sbprintf(&builder, ".doc-comment {{ color: #555; margin-bottom: 0.5em; }}\n")
	fmt.sbprintf(&builder, ".decl {{ margin-bottom: 1.5em; }}\n")
	fmt.sbprintf(&builder, ".decl-name {{ font-weight: bold; }}\n")
	fmt.sbprintf(&builder, "</style>\n")
	fmt.sbprintf(&builder, "</head>\n")
	fmt.sbprintf(&builder, "<body>\n")

	fmt.sbprintf(&builder, "<h1>{}</h1>\n", filepath.stem(canon.path))

	if canon.module_doc != "" {
		fmt.sbprintf(&builder, "<div class=\"module-doc\">\n")
		render_doc_html(&builder, canon.module_doc)
		fmt.sbprintf(&builder, "</div>\n")
	}

	for cdecl in canon.decls {
		name: string = ""
		doc: string = ""

		#partial switch d in cdecl {
		case ^semantics.CDecl_Const:
			name = base.intern_get(interner, d.name.name)
			doc = d.doc_comment
		case ^semantics.CDecl_Effect:
			name = base.intern_get(interner, d.name.name)
			doc = d.doc_comment
		case ^semantics.CDecl_Trait:
			name = base.intern_get(interner, d.name.name)
			doc = d.doc_comment
		case ^semantics.CDecl_Alias:
			name = base.intern_get(interner, d.name.name)
			doc = d.doc_comment
		case ^semantics.CDecl_Newtype:
			name = base.intern_get(interner, d.name.name)
			doc = d.doc_comment
		case ^semantics.CDecl_Import:
			name = base.intern_get(interner, d.deferred.module)
			doc = d.doc_comment
		case ^semantics.CDecl_Test:
			name = d.name
			doc = d.doc_comment
		case ^semantics.CDecl_Expect:
			doc = d.doc_comment
		case ^semantics.CDecl_Is_Impl:
			name = fmt.tprintf(
				"{} is {}",
				base.intern_get(interner, d.type_name.name),
				base.intern_get(interner, d.trait_name.name),
			)
			doc = d.doc_comment
		}

		if name == "" && doc == "" {
			continue
		}

		fmt.sbprintf(&builder, "<div class=\"decl\">\n")
		if name != "" {
			fmt.sbprintf(&builder, "<span class=\"decl-name\">{}</span>\n", html_escape(name))
		}
		if doc != "" {
			fmt.sbprintf(&builder, "<div class=\"doc-comment\">\n")
			render_doc_html(&builder, doc)
			fmt.sbprintf(&builder, "</div>\n")
		}
		fmt.sbprintf(&builder, "</div>\n")
	}

	fmt.sbprintf(&builder, "</body>\n")
	fmt.sbprintf(&builder, "</html>\n")

	dir := filepath.dir(canon.path)
	stem := filepath.stem(canon.path)
	output_path := fmt.tprintf("{}/{}.html", dir, stem)

	html_content := strings.to_string(builder)
	write_err := os.write_entire_file_from_bytes(output_path, transmute([]byte)html_content)
	if write_err != nil {
		fmt.eprintfln("error writing doc file: {}", write_err)
	} else {
		fmt.printfln("generated docs: {} -> {}", canon.path, output_path)
	}
}

render_doc_html :: proc(builder: ^strings.Builder, doc: string) {
	lines, _ := strings.split(doc, "\n")
	for i in 0 ..< len(lines) {
		line := lines[i]
		if strings.has_prefix(line, "//#") {
			continue
		}
		strings.write_string(builder, html_escape(line))
		if i < len(lines) - 1 {
			strings.write_byte(builder, '\n')
		}
	}
}

html_escape :: proc(s: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.allocator)
	for ch in s {
		switch ch {
		case '<':
			strings.write_string(&b, "&lt;")
		case '>':
			strings.write_string(&b, "&gt;")
		case '&':
			strings.write_string(&b, "&amp;")
		case '"':
			strings.write_string(&b, "&quot;")
		case:
			strings.write_rune(&b, ch)
		}
	}
	return strings.to_string(b)
}

