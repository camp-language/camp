package e2e

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

Toml_Value :: union {
	string,
	int,
	bool,
}

Toml_Entry :: struct {
	key:   string,
	value: Toml_Value,
}

Toml_Dict :: struct {
	entries: [dynamic]Toml_Entry,
}

toml_parse :: proc(input: string, allocator: mem.Allocator) -> Toml_Dict {
	dict: Toml_Dict
	dict.entries = make([dynamic]Toml_Entry, 0, 16, allocator)

	pos: int = 0
	for pos < len(input) {
		pos = skip_whitespace_and_newlines(input, pos)
		if pos >= len(input) { break }

		if input[pos] == '#' {
			pos = skip_comment(input, pos)
			continue
		}

		key_start := pos
		for pos < len(input) && input[pos] != '=' && input[pos] != '\n' {
			pos += 1
		}
		if pos >= len(input) || input[pos] != '=' { break }
		key := strings.trim_space(input[key_start:pos])
		pos += 1

		pos = skip_whitespace_and_newlines(input, pos)
		if pos >= len(input) { break }

		value: Toml_Value
		if input[pos] == '"' {
			if pos + 2 < len(input) && input[pos+1] == '"' && input[pos+2] == '"' {
				value, pos = parse_multiline_string(input, pos + 3, allocator)
			} else {
				value, pos = parse_string(input, pos, allocator)
			}
		} else if input[pos] == 't' || input[pos] == 'f' {
			value, pos = parse_bool(input, pos)
		} else {
			value, pos = parse_integer(input, pos)
		}

		append(&dict.entries, Toml_Entry{key = key, value = value})
	}

	return dict
}

toml_get :: proc(dict: ^Toml_Dict, key: string) -> (Toml_Value, bool) {
	for entry in dict.entries {
		if entry.key == key {
			return entry.value, true
		}
	}
	return Toml_Value(nil), false
}

toml_write :: proc(dict: ^Toml_Dict, buf: ^strings.Builder) {
	first := true
	for entry in dict.entries {
		if !first {
			fmt.sbprintf(buf, "\n")
		}
		first = false
		switch v in entry.value {
		case string:
			if strings.contains(v, "\n") {
				fmt.sbprintf(buf, "{} = \"\"\"\n{}\"\"\"", entry.key, v)
			} else {
				fmt.sbprintf(buf, "{} = \"{}\"", entry.key, v)
			}
		case int:
			fmt.sbprintf(buf, "{} = {}", entry.key, v)
		case bool:
			fmt.sbprintf(buf, "{} = {}", entry.key, v)
		case:
			fmt.sbprintf(buf, "{} = <unknown>", entry.key)
		}
	}
	fmt.sbprintf(buf, "\n")
}

skip_whitespace_and_newlines :: proc(input: string, start: int) -> int {
	p := start
	for p < len(input) && (input[p] == ' ' || input[p] == '\t' || input[p] == '\n' || input[p] == '\r') {
		p += 1
	}
	return p
}

skip_comment :: proc(input: string, start: int) -> int {
	p := start
	for p < len(input) && input[p] != '\n' {
		p += 1
	}
	return p
}

parse_string :: proc(input: string, start: int, allocator: mem.Allocator) -> (Toml_Value, int) {
	p := start
	if p >= len(input) || input[p] != '"' {
		return Toml_Value(""), p
	}
	p += 1

	content_start := p
	for p < len(input) && input[p] != '"' {
		if input[p] == '\\' && p + 1 < len(input) {
			p += 2
		} else {
			p += 1
		}
	}

	raw := input[content_start:p]
	s, err := strings.clone(raw, allocator)
	if err != nil {
		return Toml_Value(""), p + 1
	}
	return Toml_Value(s), p + 1
}

parse_multiline_string :: proc(input: string, start: int, allocator: mem.Allocator) -> (Toml_Value, int) {
	p := start
	if p < len(input) && input[p] == '\n' {
		p += 1
	}
	if p < len(input) && input[p] == '\r' {
		p += 1
	}

	content_start := p
	for p + 2 < len(input) {
		if input[p] == '"' && input[p+1] == '"' && input[p+2] == '"' {
			break
		}
		p += 1
	}

	raw := input[content_start:p]
	s, err := strings.clone(raw, allocator)
	if err != nil {
		return Toml_Value(""), p + 3
	}
	return Toml_Value(s), p + 3
}

parse_bool :: proc(input: string, start: int) -> (Toml_Value, int) {
	p := start
	if strings.has_prefix(input[p:], "true") {
		return Toml_Value(true), p + 4
	}
	if strings.has_prefix(input[p:], "false") {
		return Toml_Value(false), p + 5
	}
	return Toml_Value(false), p
}

parse_integer :: proc(input: string, start: int) -> (Toml_Value, int) {
	p := start
	if p < len(input) && (input[p] == '-' || input[p] == '+') {
		p += 1
	}
	for p < len(input) && input[p] >= '0' && input[p] <= '9' {
		p += 1
	}
	num_str := input[start:p]
	val, ok := strconv.parse_int(num_str)
	if !ok {
		return Toml_Value(0), p
	}
	return Toml_Value(val), p
}
