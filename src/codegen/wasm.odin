package codegen

import "camp:base"

copy_dynamic_bytes :: proc(buf: [dynamic]u8) -> []u8 {
	result := make([]u8, len(buf))
	copy(result, buf[:])
	return result
}

Wasm_Value_Type :: enum u8 {
	I32     = 0x7F,
	I64     = 0x7E,
	F32     = 0x7D,
	F64     = 0x7C,
	Funcref = 0x70,
}

Wasm_Block_Type :: enum u8 {
	Void = 0x40,
	I32  = 0x7F,
	I64  = 0x7E,
	F32  = 0x7D,
	F64  = 0x7C,
}

Wasm_Module :: struct {
	types:     [dynamic]Wasm_Func_Type,
	imports:   [dynamic]Wasm_Import,
	functions: [dynamic]int,
	tables:    [dynamic]Wasm_Table,
	memories:  [dynamic]Wasm_Memory,
	globals:   [dynamic]Wasm_Global,
	exports:   [dynamic]Wasm_Export,
	start:     int,
	elements:  [dynamic]Wasm_Element,
	codes:     [dynamic]Wasm_Code,
	datas:     [dynamic]Wasm_Data,
}

Wasm_Func_Type :: struct {
	params:  []Wasm_Value_Type,
	results: []Wasm_Value_Type,
}

Wasm_Import :: struct {
	module: string,
	field:  string,
	kind:   Wasm_External_Kind,
	index:  int,
}

Wasm_External_Kind :: enum u8 {
	Func   = 0,
	Table  = 1,
	Memory = 2,
	Global = 3,
}

Wasm_Table :: struct {
	elem_type: Wasm_Value_Type,
	min:       u32,
	max:       u32,
	has_max:   bool,
}

Wasm_Memory :: struct {
	min:     u32,
	max:     u32,
	has_max: bool,
	shared:  bool,
}

Wasm_Global :: struct {
	type:    Wasm_Value_Type,
	mutable: bool,
	init:    []u8,
}

Wasm_Export :: struct {
	name:  string,
	kind:  Wasm_External_Kind,
	index: int,
}

Wasm_Element :: struct {
	table_idx: int,
	offset:    []u8,
	func_idxs: []int,
}

Wasm_Code :: struct {
	locals: []Wasm_Local_Decl,
	body:   []u8,
}

Wasm_Local_Decl :: struct {
	count: u32,
	type:  Wasm_Value_Type,
}

Wasm_Data :: struct {
	mem_idx: int,
	offset:  []u8,
	bytes:   []u8,
}

Wasm_I32_Const :: struct {
	value: i32,
}
Wasm_I64_Const :: struct {
	value: i64,
}
Wasm_F32_Const :: struct {
	value: f32,
}
Wasm_F64_Const :: struct {
	value: f64,
}
Wasm_Local_Get :: struct {
	index: u32,
}
Wasm_Local_Set :: struct {
	index: u32,
}
Wasm_Local_Tee :: struct {
	index: u32,
}
Wasm_Global_Get :: struct {
	index: u32,
}
Wasm_Global_Set :: struct {
	index: u32,
}
Wasm_I32_Add :: struct {}
Wasm_I64_Add :: struct {}
Wasm_I32_Sub :: struct {}
Wasm_I64_Sub :: struct {}
Wasm_I32_Mul :: struct {}
Wasm_I64_Mul :: struct {}
Wasm_I32_Eq :: struct {}
Wasm_I32_Ne :: struct {}
Wasm_I32_Eqz :: struct {}
Wasm_I32_Lt_S :: struct {}
Wasm_I32_Lt_U :: struct {}
Wasm_I32_Gt_S :: struct {}
Wasm_I32_Gt_U :: struct {}
Wasm_I32_Le_S :: struct {}
Wasm_I32_Le_U :: struct {}
Wasm_I32_Ge_S :: struct {}
Wasm_I32_Ge_U :: struct {}
Wasm_I64_Eq :: struct {}
Wasm_I64_Ne :: struct {}
Wasm_I64_Lt_S :: struct {}
Wasm_I64_Gt_S :: struct {}
Wasm_I64_Le_S :: struct {}
Wasm_I64_Ge_S :: struct {}
Wasm_I32_And :: struct {}
Wasm_I32_Or :: struct {}
Wasm_I32_Xor :: struct {}
Wasm_I32_Shl :: struct {}
Wasm_I32_Shr_S :: struct {}
Wasm_I32_Shr_U :: struct {}
Wasm_I32_Div_S :: struct {}
Wasm_I32_Div_U :: struct {}
Wasm_I32_Rem_S :: struct {}
Wasm_I32_Rem_U :: struct {}
Wasm_I64_And :: struct {}
Wasm_I64_Or :: struct {}
Wasm_I64_Xor :: struct {}
Wasm_I64_Shl :: struct {}
Wasm_I64_Shr_S :: struct {}
Wasm_I64_Shr_U :: struct {}
Wasm_I64_Div_S :: struct {}
Wasm_I64_Div_U :: struct {}
Wasm_I64_Rem_S :: struct {}
Wasm_I64_Rem_U :: struct {}
Wasm_Call :: struct {
	index: u32,
}
Wasm_Call_Indirect :: struct {
	type_idx:  u32,
	table_idx: u32,
}
Wasm_Return_Call :: struct {
	index: u32,
}
Wasm_Return_Call_Indirect :: struct {
	type_idx:  u32,
	table_idx: u32,
}
Wasm_Br :: struct {
	label: u32,
}
Wasm_Br_If :: struct {
	label: u32,
}
Wasm_BrTable :: struct {
	targets:     []u32,
	default_idx: u32,
}
Wasm_Return :: struct {}
Wasm_Drop :: struct {}
Wasm_Select :: struct {}
Wasm_I32_Load :: struct {
	align:  u32,
	offset: u32,
}
Wasm_I32_Load8U :: struct {
	align:  u32,
	offset: u32,
}
Wasm_I64_Load :: struct {
	align:  u32,
	offset: u32,
}
Wasm_I32_Store :: struct {
	align:  u32,
	offset: u32,
}
Wasm_I32_Store8 :: struct {
	align:  u32,
	offset: u32,
}
Wasm_I64_Store :: struct {
	align:  u32,
	offset: u32,
}
Wasm_Memory_Copy :: struct {}
Wasm_F64_Store :: struct {
	align:  u32,
	offset: u32,
}
Wasm_F32_Store :: struct {
	align:  u32,
	offset: u32,
}
Wasm_F64_Load :: struct {
	align:  u32,
	offset: u32,
}
Wasm_F64_Lt :: struct {}
Wasm_F64_Gt :: struct {}
Wasm_F64_Add :: struct {}
Wasm_F64_Sub :: struct {}
Wasm_F64_Mul :: struct {}
Wasm_F64_Div :: struct {}
Wasm_F64_Eq :: struct {}
Wasm_F64_Ne :: struct {}
Wasm_F64_Le :: struct {}
Wasm_F64_Ge :: struct {}
Wasm_Memory_Size :: struct {}
Wasm_Memory_Grow :: struct {}
Wasm_Block :: struct {
	block_type: Wasm_Block_Type,
}
Wasm_Loop :: struct {
	block_type: Wasm_Block_Type,
}
Wasm_If :: struct {
	block_type: Wasm_Block_Type,
}
Wasm_Else :: struct {}
Wasm_End :: struct {}
Wasm_Nop :: struct {}
Wasm_Unreachable :: struct {}
Wasm_I32_Wrap_I64 :: struct {}
Wasm_I64_Extend_I32_S :: struct {}
Wasm_F64_Promote :: struct {}
Wasm_Ref_Null :: struct {
	heap_type: u8,
}
Wasm_Ref_Func :: struct {
	index: u32,
}
Wasm_Atomic_Fence :: struct {}

Wasm_Atomic_Op :: enum {
	Load,
	Store,
	RMW_Add,
	RMW_Sub,
	RMW_And,
	RMW_Or,
	RMW_Xor,
	RMW_Xchg,
	RMW_CmpXchg,
	Notify,
	Wait32,
	Wait64,
}

Wasm_Atomic_Width :: enum {
	I32,
	I64,
	I32_8,
	I32_16,
	I64_8,
	I64_16,
	I64_32,
}

Wasm_Atomic_Mem :: struct {
	op:     Wasm_Atomic_Op,
	width:  Wasm_Atomic_Width,
	align:  u32,
	offset: u32,
}

ATOMIC_PREFIX :: u8(0xFE)

atomic_opcode :: proc(op: Wasm_Atomic_Op, width: Wasm_Atomic_Width) -> u8 {
	base := u8(0)
	switch op {
	case .Load:
		base = 0x10
	case .Store:
		base = 0x17
	case .RMW_Add:
		base = 0x1E
	case .RMW_Sub:
		base = 0x25
	case .RMW_And:
		base = 0x2C
	case .RMW_Or:
		base = 0x33
	case .RMW_Xor:
		base = 0x3A
	case .RMW_Xchg:
		base = 0x41
	case .RMW_CmpXchg:
		base = 0x48
	case .Notify:
		return 0x00
	case .Wait32:
		return 0x01
	case .Wait64:
		return 0x02
	}
	offset := u8(0)
	switch width {
	case .I32:
		offset = 0
	case .I64:
		offset = 1
	case .I32_8:
		offset = 2
	case .I32_16:
		offset = 3
	case .I64_8:
		offset = 4
	case .I64_16:
		offset = 5
	case .I64_32:
		offset = 6
	}
	return base + offset
}

Wasm_Instruction :: union {
	Wasm_I32_Const,
	Wasm_I64_Const,
	Wasm_F32_Const,
	Wasm_F64_Const,
	Wasm_Local_Get,
	Wasm_Local_Set,
	Wasm_Local_Tee,
	Wasm_Global_Get,
	Wasm_Global_Set,
	Wasm_I32_Add,
	Wasm_I64_Add,
	Wasm_I32_Sub,
	Wasm_I64_Sub,
	Wasm_I32_Mul,
	Wasm_I64_Mul,
	Wasm_I32_Eq,
	Wasm_I32_Ne,
	Wasm_I32_Eqz,
	Wasm_I32_Lt_S,
	Wasm_I32_Lt_U,
	Wasm_I32_Gt_S,
	Wasm_I32_Gt_U,
	Wasm_I32_Le_S,
	Wasm_I32_Le_U,
	Wasm_I32_Ge_S,
	Wasm_I32_Ge_U,
	Wasm_I64_Eq,
	Wasm_I64_Ne,
	Wasm_I64_Lt_S,
	Wasm_I64_Gt_S,
	Wasm_I64_Le_S,
	Wasm_I64_Ge_S,
	Wasm_I32_And,
	Wasm_I32_Or,
	Wasm_I32_Xor,
	Wasm_I32_Shl,
	Wasm_I32_Shr_S,
	Wasm_I32_Shr_U,
	Wasm_I32_Div_S,
	Wasm_I32_Div_U,
	Wasm_I32_Rem_S,
	Wasm_I32_Rem_U,
	Wasm_I64_And,
	Wasm_I64_Or,
	Wasm_I64_Xor,
	Wasm_I64_Shl,
	Wasm_I64_Shr_S,
	Wasm_I64_Shr_U,
	Wasm_I64_Div_S,
	Wasm_I64_Div_U,
	Wasm_I64_Rem_S,
	Wasm_I64_Rem_U,
	Wasm_Call,
	Wasm_Call_Indirect,
	Wasm_Return_Call,
	Wasm_Return_Call_Indirect,
	Wasm_Br,
	Wasm_Br_If,
	Wasm_BrTable,
	Wasm_Return,
	Wasm_Drop,
	Wasm_Select,
	Wasm_I32_Load,
	Wasm_I32_Load8U,
	Wasm_I64_Load,
	Wasm_I32_Store,
	Wasm_I32_Store8,
	Wasm_I64_Store,
	Wasm_F64_Store,
	Wasm_F32_Store,
	Wasm_F64_Load,
	Wasm_F64_Lt,
	Wasm_F64_Gt,
	Wasm_F64_Add,
	Wasm_F64_Sub,
	Wasm_F64_Mul,
	Wasm_F64_Div,
	Wasm_F64_Eq,
	Wasm_F64_Ne,
	Wasm_F64_Le,
	Wasm_F64_Ge,
	Wasm_Memory_Size,
	Wasm_Memory_Grow,
	Wasm_Memory_Copy,
	Wasm_Block,
	Wasm_Loop,
	Wasm_If,
	Wasm_Else,
	Wasm_End,
	Wasm_Nop,
	Wasm_Unreachable,
	Wasm_I32_Wrap_I64,
	Wasm_I64_Extend_I32_S,
	Wasm_F64_Promote,
	Wasm_Ref_Null,
	Wasm_Ref_Func,
	Wasm_Atomic_Fence,
	Wasm_Atomic_Mem,
}

emit_instruction :: proc(instr: Wasm_Instruction, buf: ^[dynamic]u8) {
	switch i in instr {
	case Wasm_I32_Const:
		append(buf, 0x41)
		encode_s32_leb128(i.value, buf)
	case Wasm_I64_Const:
		append(buf, 0x42)
		encode_s64_leb128(i.value, buf)
	case Wasm_F32_Const:
		append(buf, 0x43)
		bits := transmute(u32)f32(i.value)
		append(buf, u8(bits & 0xFF))
		append(buf, u8((bits >> 8) & 0xFF))
		append(buf, u8((bits >> 16) & 0xFF))
		append(buf, u8((bits >> 24) & 0xFF))
	case Wasm_F64_Const:
		append(buf, 0x44)
		bits := transmute(u64)f64(i.value)
		append(buf, u8(bits & 0xFF))
		append(buf, u8((bits >> 8) & 0xFF))
		append(buf, u8((bits >> 16) & 0xFF))
		append(buf, u8((bits >> 24) & 0xFF))
		append(buf, u8((bits >> 32) & 0xFF))
		append(buf, u8((bits >> 40) & 0xFF))
		append(buf, u8((bits >> 48) & 0xFF))
		append(buf, u8((bits >> 56) & 0xFF))
	case Wasm_Local_Get:
		append(buf, 0x20)
		encode_u32_leb128(i.index, buf)
	case Wasm_Local_Set:
		append(buf, 0x21)
		encode_u32_leb128(i.index, buf)
	case Wasm_Local_Tee:
		append(buf, 0x22)
		encode_u32_leb128(i.index, buf)
	case Wasm_Global_Get:
		append(buf, 0x23)
		encode_u32_leb128(i.index, buf)
	case Wasm_Global_Set:
		append(buf, 0x24)
		encode_u32_leb128(i.index, buf)
	case Wasm_I32_Add:
		append(buf, 0x6A)
	case Wasm_I64_Add:
		append(buf, 0x7C)
	case Wasm_I32_Sub:
		append(buf, 0x6B)
	case Wasm_I64_Sub:
		append(buf, 0x7D)
	case Wasm_I32_Mul:
		append(buf, 0x6C)
	case Wasm_I64_Mul:
		append(buf, 0x7E)
	case Wasm_I32_Eq:
		append(buf, 0x46)
	case Wasm_I32_Ne:
		append(buf, 0x47)
	case Wasm_I32_Eqz:
		append(buf, 0x45)
	case Wasm_I32_Lt_S:
		append(buf, 0x48)
	case Wasm_I32_Lt_U:
		append(buf, 0x49)
	case Wasm_I32_Gt_S:
		append(buf, 0x4A)
	case Wasm_I32_Gt_U:
		append(buf, 0x4B)
	case Wasm_I32_Le_S:
		append(buf, 0x4C)
	case Wasm_I32_Le_U:
		append(buf, 0x4D)
	case Wasm_I32_Ge_S:
		append(buf, 0x4E)
	case Wasm_I32_Ge_U:
		append(buf, 0x4F)
	case Wasm_I64_Eq:
		append(buf, 0x51)
	case Wasm_I64_Ne:
		append(buf, 0x52)
	case Wasm_I64_Lt_S:
		append(buf, 0x53)
	case Wasm_I64_Gt_S:
		append(buf, 0x55)
	case Wasm_I64_Le_S:
		append(buf, 0x57)
	case Wasm_I64_Ge_S:
		append(buf, 0x59)
	case Wasm_I32_And:
		append(buf, 0x71)
	case Wasm_I32_Or:
		append(buf, 0x72)
	case Wasm_I32_Xor:
		append(buf, 0x73)
	case Wasm_I32_Shl:
		append(buf, 0x74)
	case Wasm_I32_Shr_S:
		append(buf, 0x75)
	case Wasm_I32_Shr_U:
		append(buf, 0x76)
	case Wasm_I32_Div_S:
		append(buf, 0x6D)
	case Wasm_I32_Div_U:
		append(buf, 0x6E)
	case Wasm_I32_Rem_S:
		append(buf, 0x6F)
	case Wasm_I32_Rem_U:
		append(buf, 0x70)
	case Wasm_I64_And:
		append(buf, 0x83)
	case Wasm_I64_Or:
		append(buf, 0x84)
	case Wasm_I64_Xor:
		append(buf, 0x85)
	case Wasm_I64_Shl:
		append(buf, 0x86)
	case Wasm_I64_Shr_S:
		append(buf, 0x87)
	case Wasm_I64_Shr_U:
		append(buf, 0x88)
	case Wasm_I64_Div_S:
		append(buf, 0x7F)
	case Wasm_I64_Div_U:
		append(buf, 0x80)
	case Wasm_I64_Rem_S:
		append(buf, 0x81)
	case Wasm_I64_Rem_U:
		append(buf, 0x82)
	case Wasm_Call:
		append(buf, 0x10)
		encode_u32_leb128(i.index, buf)
	case Wasm_Call_Indirect:
		append(buf, 0x11)
		encode_u32_leb128(i.type_idx, buf)
		encode_u32_leb128(i.table_idx, buf)
	case Wasm_Return_Call:
		append(buf, 0x12)
		encode_u32_leb128(i.index, buf)
	case Wasm_Return_Call_Indirect:
		append(buf, 0x13)
		encode_u32_leb128(i.type_idx, buf)
		encode_u32_leb128(i.table_idx, buf)
	case Wasm_Br:
		append(buf, 0x0C)
		encode_u32_leb128(i.label, buf)
	case Wasm_Br_If:
		append(buf, 0x0D)
		encode_u32_leb128(i.label, buf)
	case Wasm_BrTable:
		append(buf, 0x0E)
		encode_u32_leb128(u32(len(i.targets)), buf)
		for t in i.targets {
			encode_u32_leb128(t, buf)
		}
		encode_u32_leb128(i.default_idx, buf)
	case Wasm_Return:
		append(buf, 0x0F)
	case Wasm_Drop:
		append(buf, 0x1A)
	case Wasm_Select:
		append(buf, 0x1B)
	case Wasm_I32_Load:
		append(buf, 0x28)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_I32_Load8U:
		append(buf, 0x2C)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_I64_Load:
		append(buf, 0x29)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_I32_Store:
		append(buf, 0x36)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_I32_Store8:
		append(buf, 0x3A)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_I64_Store:
		append(buf, 0x37)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_F64_Store:
		append(buf, 0x39)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_F32_Store:
		append(buf, 0x38)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_F64_Load:
		append(buf, 0x2B)
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	case Wasm_F64_Lt:
		append(buf, 0x63)
	case Wasm_F64_Gt:
		append(buf, 0x64)
	case Wasm_F64_Add:
		append(buf, 0xA0)
	case Wasm_F64_Sub:
		append(buf, 0xA1)
	case Wasm_F64_Mul:
		append(buf, 0xA2)
	case Wasm_F64_Div:
		append(buf, 0xA3)
	case Wasm_F64_Eq:
		append(buf, 0x61)
	case Wasm_F64_Ne:
		append(buf, 0x62)
	case Wasm_F64_Le:
		append(buf, 0x65)
	case Wasm_F64_Ge:
		append(buf, 0x66)
	case Wasm_Memory_Size:
		append(buf, 0x3F)
		append(buf, 0x00)
	case Wasm_Memory_Grow:
		append(buf, 0x40)
		append(buf, 0x00)
	case Wasm_Memory_Copy:
		append(buf, 0xFC)
		append(buf, 0x0A)
		append(buf, 0x00)
		append(buf, 0x00)
	case Wasm_Block:
		append(buf, 0x02)
		append(buf, u8(i.block_type))
	case Wasm_Loop:
		append(buf, 0x03)
		append(buf, u8(i.block_type))
	case Wasm_If:
		append(buf, 0x04)
		append(buf, u8(i.block_type))
	case Wasm_Else:
		append(buf, 0x05)
	case Wasm_End:
		append(buf, 0x0B)
	case Wasm_Nop:
		append(buf, 0x01)
	case Wasm_Unreachable:
		append(buf, 0x00)
	case Wasm_I32_Wrap_I64:
		append(buf, 0xA7)
	case Wasm_I64_Extend_I32_S:
		append(buf, 0xAC)
	case Wasm_F64_Promote:
		append(buf, 0xBB)
	case Wasm_Ref_Null:
		append(buf, 0xD0)
		append(buf, i.heap_type)
	case Wasm_Ref_Func:
		append(buf, 0xD2)
		encode_u32_leb128(i.index, buf)
	case Wasm_Atomic_Fence:
		append(buf, ATOMIC_PREFIX)
		append(buf, 0x03)
		encode_u32_leb128(0, buf)
	case Wasm_Atomic_Mem:
		append(buf, ATOMIC_PREFIX)
		append(buf, atomic_opcode(i.op, i.width))
		encode_u32_leb128(i.align, buf)
		encode_u32_leb128(i.offset, buf)
	}
}

encode_u32_leb128 :: proc(value: u32, buf: ^[dynamic]u8) {
	v: u32 = value
	for {
		byte: u8 = u8(v & 0x7F)
		v >>= 7
		if v != 0 {
			byte |= 0x80
		}
		append(buf, byte)
		if v == 0 {
			break
		}
	}
}

encode_s32_leb128 :: proc(value: i32, buf: ^[dynamic]u8) {
	v: i32 = value
	for {
		byte: u8 = u8(v & 0x7F)
		v >>= 7
		if (v == 0 && (byte & 0x40) == 0) || (v == -1 && (byte & 0x40) != 0) {
			append(buf, byte)
			break
		}
		append(buf, byte | 0x80)
	}
}

encode_u64_leb128 :: proc(value: u64, buf: ^[dynamic]u8) {
	v: u64 = value
	for {
		byte: u8 = u8(v & 0x7F)
		v >>= 7
		if v != 0 {
			byte |= 0x80
		}
		append(buf, byte)
		if v == 0 {
			break
		}
	}
}

encode_s64_leb128 :: proc(value: i64, buf: ^[dynamic]u8) {
	v: i64 = value
	for {
		byte: u8 = u8(v & 0x7F)
		v >>= 7
		if (v == 0 && (byte & 0x40) == 0) || (v == -1 && (byte & 0x40) != 0) {
			append(buf, byte)
			break
		}
		append(buf, byte | 0x80)
	}
}

wasm_encode_string :: proc(s: string, buf: ^[dynamic]u8) {
	encode_u32_leb128(u32(len(s)), buf)
	for c in s {
		append(buf, u8(c))
	}
}

wasm_encode_section_raw :: proc(id: u8, content: []u8, buf: ^[dynamic]u8) {
	append(buf, id)
	encode_u32_leb128(u32(len(content)), buf)
	for b in content {
		append(buf, b)
	}
}

wasm_encode_section :: proc(
	section_id: u8,
	buf: ^[dynamic]u8,
	body: proc(mod: Wasm_Module, content: ^[dynamic]u8),
	mod: Wasm_Module,
) {
	content: [dynamic]u8
	body(mod, &content)
	wasm_encode_section_raw(section_id, content[:], buf)
	delete(content)
}

wasm_serialize :: proc(mod: Wasm_Module) -> [dynamic]u8 {
	buf: [dynamic]u8
	buf = make([dynamic]u8, 0, CODE_BUF_SECTION)

	append(&buf, 0x00)
	append(&buf, 0x61)
	append(&buf, 0x73)
	append(&buf, 0x6D)
	append(&buf, 0x01)
	append(&buf, 0x00)
	append(&buf, 0x00)
	append(&buf, 0x00)

	if len(mod.types) > 0 {
		wasm_encode_section(1, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.types)), content)
				for ft in mod.types {
					append(content, 0x60)
					encode_u32_leb128(u32(len(ft.params)), content)
					for p in ft.params {
						append(content, u8(p))
					}
					encode_u32_leb128(u32(len(ft.results)), content)
					for r in ft.results {
						append(content, u8(r))
					}
				}
			}, mod)
	}

	if len(mod.imports) > 0 {
		wasm_encode_section(2, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.imports)), content)
				for imp in mod.imports {
					wasm_encode_string(imp.module, content)
					wasm_encode_string(imp.field, content)
					append(content, u8(imp.kind))
					switch imp.kind {
					case .Func:
						encode_u32_leb128(u32(imp.index), content)
					case .Table:
						append(content, u8(Wasm_Value_Type.Funcref))
						if imp.index >= 0 {
							append(content, 1)
							encode_u32_leb128(0, content)
							encode_u32_leb128(u32(imp.index), content)
						} else {
							append(content, 0)
							encode_u32_leb128(0, content)
						}
					case .Memory:
						append(content, 0)
						encode_u32_leb128(1, content)
					case .Global:
						append(content, u8(Wasm_Value_Type.I32))
						append(content, 0)
					}
				}
			}, mod)
	}

	if len(mod.functions) > 0 {
		wasm_encode_section(3, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.functions)), content)
				for idx in mod.functions {
					encode_u32_leb128(u32(idx), content)
				}
			}, mod)
	}

	if len(mod.tables) > 0 {
		wasm_encode_section(4, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.tables)), content)
				for tbl in mod.tables {
					append(content, u8(tbl.elem_type))
					if tbl.has_max {
						append(content, 1)
						encode_u32_leb128(tbl.min, content)
						encode_u32_leb128(tbl.max, content)
					} else {
						append(content, 0)
						encode_u32_leb128(tbl.min, content)
					}
				}
			}, mod)
	}

	if len(mod.memories) > 0 {
		wasm_encode_section(
			5,
			&buf,
			proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.memories)), content)
				for mem in mod.memories {
					if mem.has_max && mem.shared {
						append(content, 3) // shared + has_max
						encode_u32_leb128(mem.min, content)
						encode_u32_leb128(mem.max, content)
					} else if mem.has_max {
						append(content, 1)
						encode_u32_leb128(mem.min, content)
						encode_u32_leb128(mem.max, content)
					} else {
						append(content, 0)
						encode_u32_leb128(mem.min, content)
					}
				}
			},
			mod,
		)
	}

	if len(mod.globals) > 0 {
		wasm_encode_section(6, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.globals)), content)
				for g in mod.globals {
					append(content, u8(g.type))
					if g.mutable {
						append(content, 1)
					} else {
						append(content, 0)
					}
					for b in g.init {
						append(content, b)
					}
					append(content, 0x0B)
				}
			}, mod)
	}

	if len(mod.exports) > 0 {
		wasm_encode_section(7, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.exports)), content)
				for exp in mod.exports {
					wasm_encode_string(exp.name, content)
					append(content, u8(exp.kind))
					encode_u32_leb128(u32(exp.index), content)
				}
			}, mod)
	}

	if mod.start >= 0 {
		wasm_encode_section(8, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(mod.start), content)
			}, mod)
	}

	if len(mod.elements) > 0 {
		wasm_encode_section(9, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.elements)), content)
				for elem in mod.elements {
					encode_u32_leb128(u32(elem.table_idx), content)
					for b in elem.offset {
						append(content, b)
					}
					append(content, 0x0B)
					encode_u32_leb128(u32(len(elem.func_idxs)), content)
					for idx in elem.func_idxs {
						encode_u32_leb128(u32(idx), content)
					}
				}
			}, mod)
	}

	if len(mod.codes) > 0 {
		wasm_encode_section(10, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.codes)), content)
				for code in mod.codes {
					body_buf: [dynamic]u8
					body_buf = make([dynamic]u8, 0, CODE_BUF_XL)

					encode_u32_leb128(u32(len(code.locals)), &body_buf)
					for loc in code.locals {
						encode_u32_leb128(loc.count, &body_buf)
						append(&body_buf, u8(loc.type))
					}
					for b in code.body {
						append(&body_buf, b)
					}

					encode_u32_leb128(u32(len(body_buf)), content)
					for b in body_buf {
						append(content, b)
					}
					delete(body_buf)
				}
			}, mod)
	}

	if len(mod.datas) > 0 {
		wasm_encode_section(11, &buf, proc(mod: Wasm_Module, content: ^[dynamic]u8) {
				encode_u32_leb128(u32(len(mod.datas)), content)
				for d in mod.datas {
					encode_u32_leb128(u32(d.mem_idx), content)
					for b in d.offset {
						append(content, b)
					}
					append(content, 0x0B)
					encode_u32_leb128(u32(len(d.bytes)), content)
					for b in d.bytes {
						append(content, b)
					}
				}
			}, mod)
	}

	return buf
}

wasm_module_destroy :: proc(mod: ^Wasm_Module) {
	for ft in mod.types {
		delete(ft.params)
		delete(ft.results)
	}
	delete(mod.types)
	delete(mod.imports)
	delete(mod.functions)
	delete(mod.tables)
	delete(mod.memories)
	for g in mod.globals {
		delete(g.init)
	}
	delete(mod.globals)
	// exports have name: string — do NOT delete strings
	delete(mod.exports)
	for elem in mod.elements {
		delete(elem.offset)
		delete(elem.func_idxs)
	}
	delete(mod.elements)
	for c in mod.codes {
		delete(c.body)
		delete(c.locals)
	}
	delete(mod.codes)
	for d in mod.datas {
		delete(d.offset)
		delete(d.bytes)
	}
	delete(mod.datas)
}

ir_wasm_type_to_value_type :: proc(t: base.IR_Wasm_Type) -> Wasm_Value_Type {
	switch t {
	case .I32:
		return .I32
	case .I64:
		return .I64
	case .F32:
		return .F32
	case .F64:
		return .F64
	// After closure conversion, function-typed values are heap-allocated
	// closure records (i32 pointers). Funcref only surfaces as the table
	// element type, never on the value stack.
	case .Funcref:
		return .I32
	case .Void:
		return .I64
	}
	return .I32
}

value_type_to_ir_wasm_type :: proc(t: Wasm_Value_Type) -> base.IR_Wasm_Type {
	switch t {
	case .I32:
		return .I32
	case .I64:
		return .I64
	case .F32:
		return .F32
	case .F64:
		return .F64
	case .Funcref:
		return .I32
	}
	return .I32
}

ir_wasm_type_to_block_type :: proc(t: base.IR_Wasm_Type) -> Wasm_Block_Type {
	switch t {
	case .I32:
		return .I32
	case .I64:
		return .I64
	case .F32:
		return .F32
	case .F64:
		return .F64
	case .Funcref, .Void:
		return .Void
	}
	return .Void
}

