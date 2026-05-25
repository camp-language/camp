package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

@(private="file")
CATALOG_BYTES :: #load("../../docs/diagnostics-catalog.md")

@(private="file")
CATALOG :: string(CATALOG_BYTES)

// Extracts the catalog section for `code` (e.g., "C0301").
// Returns (title, body) where body is everything between the section header
// and the next "### " or "## " header. Both empty if not found.
explain_lookup :: proc(code: string) -> (title: string, body: string, found: bool) {
	catalog := CATALOG
	needle := strings.concatenate({"(", code, ")"}, context.temp_allocator)
	idx := strings.index(catalog, needle)
	if idx < 0 do return "", "", false

	header_start := strings.last_index_byte(catalog[:idx], '\n')
	if header_start < 0 do header_start = 0
	else do header_start += 1
	if !strings.has_prefix(catalog[header_start:], "### ") {
		return "", "", false
	}

	header_end := strings.index_byte(catalog[header_start:], '\n')
	if header_end < 0 do return "", "", false
	header_line := catalog[header_start:header_start + header_end]

	// Extract title: "### N.M TITLE (Cxxxx) ..." → "TITLE"
	after_num := strings.index_byte(header_line, ' ')
	if after_num >= 0 {
		rest := header_line[after_num + 1:]
		after_num2 := strings.index_byte(rest, ' ')
		if after_num2 >= 0 {
			rest = rest[after_num2 + 1:]
			paren := strings.index_byte(rest, '(')
			if paren > 0 {
				title = strings.trim_space(rest[:paren])
			}
		}
	}

	body_start := header_start + header_end + 1
	rest := catalog[body_start:]
	next_section: int = -1
	cursor := 0
	for cursor < len(rest) {
		nl := strings.index_byte(rest[cursor:], '\n')
		line_end := len(rest) if nl < 0 else cursor + nl
		line := rest[cursor:line_end]
		if strings.has_prefix(line, "### ") || strings.has_prefix(line, "## ") || strings.has_prefix(line, "---") {
			next_section = cursor
			break
		}
		if nl < 0 do break
		cursor = line_end + 1
	}
	if next_section < 0 {
		body = strings.trim_space(rest)
	} else {
		body = strings.trim_space(rest[:next_section])
	}
	return title, body, true
}

run_explain :: proc(args: []string) -> int {
	if len(args) == 0 {
		if is_json_mode() {
			fmt.println(`{"ok":false,"error":"usage: camp explain <code>"}`)
		} else {
			fmt.eprintln("usage: camp explain <code>   (e.g. camp explain C0301)")
		}
		return 1
	}
	code := args[0]
	title, body, found := explain_lookup(code)

	if is_json_mode() {
		obj := make(json.Object, 4)
		obj["ok"] = json.Boolean(found)
		obj["code"] = json.String(code)
		if found {
			obj["title"] = json.String(title)
			obj["body"] = json.String(body)
		} else {
			obj["error"] = json.String("unknown code")
		}
		bytes, err := json.marshal(obj, {pretty = false})
		if err == nil {
			os.write(os.stdout, bytes)
			os.write(os.stdout, []u8{'\n'})
			delete(bytes)
		}
		return 0 if found else 1
	}

	if !found {
		fmt.eprintfln("unknown diagnostic code: {}", code)
		fmt.eprintln("see docs/diagnostics-catalog.md for the full list")
		return 1
	}
	fmt.printfln("{}: {}", code, title)
	fmt.println()
	fmt.println(body)
	return 0
}
