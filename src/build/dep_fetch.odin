package build

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// ---- Git operations ----

fetch_git_tags :: proc(source: string) -> []string {
	url := _source_to_git_url(source)
	cmd := []string{"git", "ls-remote", "--tags", "--refs", url}
	stdout, _, exit_code := run_command(cmd)
	if exit_code != 0 {return nil}

	tags := make([dynamic]string, 0, 16, context.temp_allocator)
	lines := strings.split_lines(stdout, context.temp_allocator)
	for line in lines {
		if idx := strings.last_index(line, "/"); idx >= 0 {
			tag := strings.trim_space(line[idx + 1:])
			tag = strings.trim_suffix(tag, "^{}")
			if len(tag) > 0 && (strings.has_prefix(tag, "v") || _looks_semver(tag)) {
				append(&tags, strings.clone(tag, context.temp_allocator))
			}
		}
	}
	return tags[:]
}

resolve_tag_to_rev :: proc(source: string, tag: string) -> (string, bool) {
	url := _source_to_git_url(source)
	cmd := []string{"git", "ls-remote", url, tag}
	stdout, _, exit_code := run_command(cmd)
	if exit_code != 0 {return "", false}
	parts := _split_whitespace(stdout)
	if len(parts) >= 1 {return parts[0], true}
	return "", false
}

// ---- Helpers ----

_source_to_git_url :: proc(source: string) -> string {
	if strings.has_prefix(source, "github.com/") {
		return strings.concatenate({"https://", source, ".git"}, context.temp_allocator)
	}
	if strings.has_prefix(source, "gitlab.com/") {
		return strings.concatenate({"https://", source, ".git"}, context.temp_allocator)
	}
	return strings.concatenate({"https://", source}, context.temp_allocator)
}

_looks_semver :: proc(s: string) -> bool {
	dots := 0
	for r in s {
		if r == '.' {dots += 1} else if r < '0' || r > '9' {return false}
	}
	return dots == 2
}

_split_whitespace :: proc(s: string) -> []string {
	result := make([dynamic]string, 0, 4, context.temp_allocator)
	word_start := -1
	for r, i in s {
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' {
			if word_start >= 0 {
				append(&result, s[word_start:i])
				word_start = -1
			}
		} else if word_start < 0 {
			word_start = i
		}
	}
	if word_start >= 0 && word_start < len(s) {
		append(&result, s[word_start:])
	}
	return result[:]
}

