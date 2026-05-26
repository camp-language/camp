package base

import "base:intrinsics"
import "core:strings"

Intern_ID :: distinct int

// --- Swiss Table constants ---

GROUP_WIDTH :: 8
GROUP_MASK :: int(GROUP_WIDTH - 1)

CTRL_EMPTY: u8 : 0x80
CTRL_DELETED: u8 : 0xFE

// SWAR bit-operation constants
MSB_MASK: u64 : 0x80_80_80_80_80_80_80_80
LSB_MASK: u64 : 0x01_01_01_01_01_01_01_01

// --- Intern_Table (Swiss Table + contiguous string buffer) ---

Intern_Table :: struct {
	// Swiss Table hash map
	ctrl:           [dynamic]u8, // 1 byte per slot + GROUP_WIDTH cloned tail
	id_from_slot:   [dynamic]Intern_ID, // slot → Intern_ID
	capacity:       int, // total slots (power of 2, ≥ GROUP_WIDTH)
	mask:           u32, // capacity - 1
	count:          int, // number of entries
	growth_left:    int, // capacity*7/8 - count

	// Contiguous string storage (SoA)
	string_buffer:  [dynamic]u8, // all interned strings concatenated
	string_offsets: [dynamic]u32, // Intern_ID → offset into buffer
	string_lengths: [dynamic]u32, // Intern_ID → string length
	next_id:        Intern_ID,
}

// --- SWAR helpers ---

broadcast :: #force_inline proc(b: u8) -> u64 {
	return u64(b) * 0x01_01_01_01_01_01_01_01
}

zero_byte_mask :: #force_inline proc(x: u64) -> u64 {
	return (x - LSB_MASK) & ~x & MSB_MASK
}

match_h2 :: #force_inline proc(group: u64, h2: u8) -> u64 {
	x := group ~ broadcast(h2)
	return zero_byte_mask(x)
}

match_empty :: #force_inline proc(group: u64) -> u64 {
	return match_h2(group, CTRL_EMPTY)
}

match_empty_or_deleted :: #force_inline proc(group: u64) -> u64 {
	return group & MSB_MASK
}

compress_mask :: #force_inline proc(sparse: u64) -> u64 {
	return (sparse * 0x02_04_08_10_20_40_81) >> 56
}

// Load 8 ctrl bytes starting at slot index `base` as a u64 (little-endian).
// The ctrl array has capacity + GROUP_WIDTH bytes, so this is safe for
// any base in [0, capacity) since the tail is cloned.
load_group :: #force_inline proc(ctrl: []u8, base: int) -> u64 {
	return(
		u64(ctrl[base]) |
		(u64(ctrl[base + 1]) << 8) |
		(u64(ctrl[base + 2]) << 16) |
		(u64(ctrl[base + 3]) << 24) |
		(u64(ctrl[base + 4]) << 32) |
		(u64(ctrl[base + 5]) << 40) |
		(u64(ctrl[base + 6]) << 48) |
		(u64(ctrl[base + 7]) << 56) \
	)
}

// --- FNV-1a hash ---

hash_string :: proc(s: string) -> u64 {
	h: u64 = 14695981039346656037 // FNV-1a offset basis
	for i := 0; i < len(s); i += 1 {
		h = h ~ u64(s[i])
		h = h * 1099511628211 // FNV-1a prime
	}
	return h
}

// --- Public API ---

intern_init :: proc(table: ^Intern_Table) {
	cap :: GROUP_WIDTH * 4 // 32
	table.ctrl = make([dynamic]u8, cap + GROUP_WIDTH, cap + GROUP_WIDTH)
	table.id_from_slot = make([dynamic]Intern_ID, 0, cap)
	table.capacity = cap
	table.mask = u32(cap - 1)
	table.count = 0
	table.growth_left = cap * 7 / 8

	// Initialize all ctrl bytes to EMPTY
	for i := 0; i < cap + GROUP_WIDTH; i += 1 {
		table.ctrl[i] = CTRL_EMPTY
	}

	table.string_buffer = make([dynamic]u8, 0, 4096)
	table.string_offsets = make([dynamic]u32, 0, 256)
	table.string_lengths = make([dynamic]u32, 0, 256)
	table.next_id = 0
}

intern_destroy :: proc(table: ^Intern_Table) {
	delete(table.ctrl)
	delete(table.id_from_slot)
	delete(table.string_buffer)
	delete(table.string_offsets)
	delete(table.string_lengths)
}

intern :: proc(table: ^Intern_Table, s: string) -> Intern_ID {
	hash := hash_string(s)
	h2 := u8(hash & 0x7F)
	h1 := u32(hash >> 7)

	// Probe for existing entry
	// h1 & mask gives a slot index; we align down to group boundary for load_group
	slot := h1 & table.mask
	step := u32(0)
	for {
		group_base := int(slot) & ~GROUP_MASK
		group := load_group(table.ctrl[:], group_base)

		// Check H2 matches within this group
		matches := compress_mask(match_h2(group, h2))
		for matches != 0 {
			bit := u32(intrinsics.count_trailing_zeros(matches))
			matched_slot := group_base + int(bit)
			if matched_slot < table.capacity {
				id := table.id_from_slot[matched_slot]
				offset := table.string_offsets[int(id)]
				length := table.string_lengths[int(id)]
				if length == u32(len(s)) &&
				   string(table.string_buffer[offset:offset + length]) == s {
					return id
				}
			}
			matches &= matches - 1
		}

		// Check for empty — means key not present
		empties := compress_mask(match_empty(group))
		if empties != 0 {
			break
		}

		// Advance probe (triangular sequence)
		step += 1
		slot = (h1 + step * (step + 1) / 2) & table.mask
	}

	// Not found — insert
	id := table.next_id
	table.next_id += 1

	// Store string in contiguous buffer
	offset := u32(len(table.string_buffer))
	append(&table.string_offsets, offset)
	append(&table.string_lengths, u32(len(s)))
	for i := 0; i < len(s); i += 1 {
		append(&table.string_buffer, u8(s[i]))
	}

	// Find insertion slot
	insert_slot := intern_find_insert_slot(table, h1, h2)
	table.ctrl[insert_slot] = h2
	for len(table.id_from_slot) <= insert_slot {
		append(&table.id_from_slot, Intern_ID(-1))
	}
	table.id_from_slot[insert_slot] = id
	table.count += 1
	table.growth_left -= 1

	// Resize if needed
	if table.growth_left == 0 {
		intern_grow(table)
	}

	return id
}

intern_get :: proc(table: ^Intern_Table, id: Intern_ID) -> string {
	offset := table.string_offsets[int(id)]
	length := table.string_lengths[int(id)]
	return string(table.string_buffer[offset:offset + length])
}

mangle_name :: proc(module: Intern_ID, name: Intern_ID, interner: ^Intern_Table) -> string {
	module_str := intern_get(interner, module)
	name_str := intern_get(interner, name)
	builder: strings.Builder
	strings.builder_init_len_cap(&builder, 0, len(module_str) + len(name_str) + 4)
	for i := 0; i < len(module_str); i += 1 {
		if module_str[i] == '.' {
			strings.write_byte(&builder, '_')
		} else {
			strings.write_byte(&builder, module_str[i])
		}
	}
	strings.write_string(&builder, "__")
	strings.write_string(&builder, name_str)
	result := strings.to_string(builder)
	strings.builder_destroy(&builder)
	return result
}

// --- Internal helpers ---

intern_find_insert_slot :: proc(table: ^Intern_Table, h1: u32, h2: u8) -> int {
	slot := h1 & table.mask
	step := u32(0)
	for {
		group_base := int(slot) & ~GROUP_MASK
		group := load_group(table.ctrl[:], group_base)

		// Find first empty or deleted slot in this group
		available := compress_mask(match_empty_or_deleted(group))
		if available != 0 {
			bit := u32(intrinsics.count_trailing_zeros(available))
			candidate := group_base + int(bit)
			// Must be within capacity
			if candidate < table.capacity {
				return candidate
			}
			// If candidate is in the cloned tail, find the real slot
			// (it wraps around — the real slot is candidate - capacity)
			// But since we're insert-only and the table always has room,
			// this shouldn't happen. Skip this match and try next.
			available &= available - 1
			if available != 0 {
				bit = u32(intrinsics.count_trailing_zeros(available))
				candidate = group_base + int(bit)
				if candidate < table.capacity {
					return candidate
				}
			}
		}

		step += 1
		slot = (h1 + step * (step + 1) / 2) & table.mask
	}
}

intern_grow :: proc(table: ^Intern_Table) {
	new_cap := table.capacity * 2
	if new_cap < GROUP_WIDTH * 4 {
		new_cap = GROUP_WIDTH * 4
	}

	// Save old data
	old_ctrl := table.ctrl
	old_ids := table.id_from_slot
	old_count := table.count

	// Allocate new arrays
	table.ctrl = make([dynamic]u8, new_cap + GROUP_WIDTH, new_cap + GROUP_WIDTH)
	table.id_from_slot = make([dynamic]Intern_ID, 0, new_cap)
	table.capacity = new_cap
	table.mask = u32(new_cap - 1)
	table.count = 0
	table.growth_left = new_cap * 7 / 8

	// Initialize new ctrl to EMPTY
	for i := 0; i < new_cap + GROUP_WIDTH; i += 1 {
		table.ctrl[i] = CTRL_EMPTY
	}

	// Re-insert all entries
	for slot := 0; slot < len(old_ctrl) && table.count < old_count; slot += 1 {
		ctrl_byte := old_ctrl[slot]
		if ctrl_byte == CTRL_EMPTY || ctrl_byte == CTRL_DELETED {
			continue
		}
		if slot >= table.capacity {
			continue
		}
		// This is a full slot — re-insert
		id := old_ids[slot]
		s := string(
			table.string_buffer[table.string_offsets[int(id)]:table.string_offsets[int(id)] +
			table.string_lengths[int(id)]],
		)
		hash := hash_string(s)
		h2 := u8(hash & 0x7F)
		h1 := u32(hash >> 7)

		insert_slot := intern_find_insert_slot(table, h1, h2)
		table.ctrl[insert_slot] = h2
		for len(table.id_from_slot) <= insert_slot {
			append(&table.id_from_slot, Intern_ID(-1))
		}
		table.id_from_slot[insert_slot] = id
		table.count += 1
		table.growth_left -= 1
	}

	delete(old_ctrl)
	delete(old_ids)
}

