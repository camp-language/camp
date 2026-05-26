package lsp

import "core:fmt"
import "core:mem"
import "core:os"

Transport :: struct {
	allocator: mem.Allocator,
}

transport_init :: proc(t: ^Transport, allocator: mem.Allocator) {
	t.allocator = allocator
}

read_message :: proc(t: ^Transport) -> ([]u8, bool) {
	header_buf: [4096]u8
	header_len := 0

	for {
		if header_len >= len(header_buf) - 1 {
			return nil, false
		}
		buf: [1]u8
		n, err := os.read(os.stdin, buf[:])
		if err != nil || n == 0 {
			return nil, false
		}
		header_buf[header_len] = buf[0]
		header_len += 1

		if header_len >= 4 &&
		   header_buf[header_len - 4] == '\r' &&
		   header_buf[header_len - 3] == '\n' &&
		   header_buf[header_len - 2] == '\r' &&
		   header_buf[header_len - 1] == '\n' {
			break
		}
	}

	header := string(header_buf[:header_len])

	content_length := 0
	prefix := "Content-Length: "
	prefix_len := len(prefix)
	for i in 0 ..< (header_len - prefix_len) {
		if i != 0 && header[i - 1] != '\n' {
			continue
		}
		if header[i:i + prefix_len] == prefix {
			digit_start := i + prefix_len
			j := digit_start
			for j < header_len {
				c := header[j]
				if c >= '0' && c <= '9' {
					content_length = content_length * 10 + int(c - '0')
					j += 1
				} else if c == '\r' {
					break
				} else {
					j += 1
				}
			}
			break
		}
	}

	if content_length <= 0 {
		return nil, false
	}

	body := make([]u8, content_length, t.allocator)
	total_read := 0
	for total_read < content_length {
		n, err := os.read(os.stdin, body[total_read:])
		if err != nil || n == 0 {
			delete(body, t.allocator)
			return nil, false
		}
		total_read += n
	}

	return body[:content_length], true
}

write_message :: proc(t: ^Transport, message: string) -> bool {
	header_buf: [64]u8
	header := fmt.bprintf(header_buf[:], "Content-Length: {}\r\n\r\n", len(message))
	_, err := os.write(os.stdout, transmute([]byte)header)
	if err != nil {
		return false
	}
	_, err = os.write(os.stdout, transmute([]byte)message)
	if err != nil {
		return false
	}
	_ = os.flush(os.stdout)
	return true
}

