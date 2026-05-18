package lsp

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"

read_message :: proc() -> (string, bool) {
	header_buf: [4096]u8
	header_len := 0

	for {
		if header_len >= len(header_buf) - 1 {
			return "", false
		}
		buf: [1]u8
		n, err := os.read(os.stdin, buf[:])
		if err != nil || n == 0 {
			return "", false
		}
		header_buf[header_len] = buf[0]
		header_len += 1

		if header_len >= 4 &&
			header_buf[header_len-4] == '\r' &&
			header_buf[header_len-3] == '\n' &&
			header_buf[header_len-2] == '\r' &&
			header_buf[header_len-1] == '\n' {
			break
		}
	}

	header := string(header_buf[:header_len])

	content_length := 0
	fields := strings.fields(header)
	for field in fields {
		if strings.has_prefix(field, "Content-Length:") {
			val_str := field[len("Content-Length:"):]
			val_str = strings.trim_space(val_str)
			for c in val_str {
				if c >= '0' && c <= '9' {
					content_length = content_length * 10 + int(c - '0')
				}
			}
		}
	}

	if content_length <= 0 {
		return "", false
	}

	body := make([]u8, content_length)
	total_read := 0
	for total_read < content_length {
		n, err := os.read(os.stdin, body[total_read:])
		if err != nil || n == 0 {
			delete(body)
			return "", false
		}
		total_read += n
	}

	result := string(body[:content_length])
	delete(body)
	return result, true
}

write_message :: proc(content: string) -> bool {
	builder: strings.Builder
	strings.builder_init(&builder, 4096)
	defer strings.builder_destroy(&builder)

	fmt.sbprintf(&builder, "Content-Length: {}\r\n\r\n{}", len(content), content)

	data := strings.to_string(builder)
	written, err := os.write(os.stdout, []byte(data))
	if err != nil {
		return false
	}
	os.flush(os.stdout)
	return written > 0
}
