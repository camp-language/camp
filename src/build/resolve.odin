package build

import "core:mem"
import "core:strings"

Semver :: struct {
	major: int,
	minor: int,
	patch: int,
}

semver_parse :: proc(s: string) -> (Semver, bool) {
	v := Semver{}
	t := s
	if len(t) > 0 && (t[0] == 'v' || t[0] == 'V') {t = t[1:]}
	parts := strings.split(t, ".", context.temp_allocator)
	if len(parts) != 3 {return v, false}
	for i in 0 ..< 3 {
		num := 0
		for r in parts[i] {
			if r < '0' || r > '9' {return v, false}
			num = num * 10 + int(r - '0')
		}
		switch i {
		case 0: v.major = num
		case 1: v.minor = num
		case 2: v.patch = num
		}
	}
	return v, true
}

semver_cmp :: proc(a, b: Semver) -> int {
	if a.major != b.major {return a.major - b.major}
	if a.minor != b.minor {return a.minor - b.minor}
	return a.patch - b.patch
}

// MVS: find highest tag in candidate list that satisfies >= min_ver
// and stays within the same semver compatibility range.
semver_best_match :: proc(candidates: []string, min_ver: Semver) -> string {
	best: Semver
	best_str := ""
	has_best := false
	for tag in candidates {
		v, ok := semver_parse(tag)
		if !ok {continue}
		if semver_cmp(v, min_ver) < 0 {continue}
		if min_ver.major == 0 {
			if v.minor != min_ver.minor {continue}
		} else {
			if v.major != min_ver.major {continue}
		}
		if !has_best || semver_cmp(v, best) > 0 {
			best = v
			best_str = tag
			has_best = true
		}
	}
	return best_str
}

// Resolved dependency graph entry.
Resolved_Dep :: struct {
	alias:   string,
	source:  string,
	tag:     string,
	version: string,
}

// Resolve dependencies using MVS.
// For now, this works with static tag lists (no git fetch).
// Returns the resolved list and any packages that couldn't be resolved.
resolve_mvs :: proc(
	deps: []Dependency_Info,
	tags_for_source: proc(source: string) -> []string,
	allocator: mem.Allocator,
) -> ([]Resolved_Dep, []string) {
	resolved := make([dynamic]Resolved_Dep, 0, len(deps), allocator)
	missing := make([dynamic]string, 0, 4, allocator)

	for dep in deps {
		source := dep.source
		tags := tags_for_source(source)
		if len(tags) == 0 {
			append(&missing, source)
			continue
		}

		// Parse the version constraint
		ver_str := dep.version
		if len(ver_str) >= 2 && ver_str[:2] == "v=" {
			ver_str = ver_str[2:]
		}

		min_ver, ok := semver_parse(ver_str)
		if !ok {
			append(&missing, source)
			continue
		}

		best := semver_best_match(tags, min_ver)
		if best == "" {
			append(&missing, source)
			continue
		}

		append(&resolved, Resolved_Dep{
			alias = dep.alias,
			source = source,
			tag = best,
			version = ver_str,
		})
	}

	return resolved[:], missing[:]
}
