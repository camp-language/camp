package build

import "camp:base"

// Stdlib module registry — embedded .camp source files
// These are parsed and typechecked on demand when imported by user code.
// Source is embedded from the stdlib/ directory at compiler build time via
// `#load`, so the embedded source is always identical to the on-disk file.
// (Previously these were hand-maintained string literals that drifted from
// the real stdlib/*.camp — see bean camp-24mj.)

Stdlib_Module :: struct {
	name:   string,
	source: string,
	path:   string,
}

RESULT_CAMP :: #load("../../stdlib/Result.camp", string)

PARSE_ERROR_CAMP :: #load("../../stdlib/ParseError.camp", string)

BOOL_CAMP :: #load("../../stdlib/Bool.camp", string)

STR_CAMP :: #load("../../stdlib/Str.camp", string)

LIST_CAMP :: #load("../../stdlib/List.camp", string)

ITER_CAMP :: #load("../../stdlib/Iter.camp", string)

MAP_CAMP :: #load("../../stdlib/Map.camp", string)

SET_CAMP :: #load("../../stdlib/Set.camp", string)

DISPLAY_CAMP :: #load("../../stdlib/Display.camp", string)

CHAR_CAMP :: #load("../../stdlib/Char.camp", string)

NUM_I64_CAMP :: #load("../../stdlib/Num/I64.camp", string)

NUM_I32_CAMP :: #load("../../stdlib/Num/I32.camp", string)

NUM_I16_CAMP :: #load("../../stdlib/Num/I16.camp", string)

NUM_I8_CAMP :: #load("../../stdlib/Num/I8.camp", string)

NUM_U64_CAMP :: #load("../../stdlib/Num/U64.camp", string)

NUM_U32_CAMP :: #load("../../stdlib/Num/U32.camp", string)

NUM_U16_CAMP :: #load("../../stdlib/Num/U16.camp", string)

NUM_U8_CAMP :: #load("../../stdlib/Num/U8.camp", string)

NUM_F64_CAMP :: #load("../../stdlib/Num/F64.camp", string)

NUM_F32_CAMP :: #load("../../stdlib/Num/F32.camp", string)

BYTES_CAMP :: #load("../../stdlib/Bytes.camp", string)

EQ_CAMP :: #load("../../stdlib/Eq.camp", string)

ORD_CAMP :: #load("../../stdlib/Ord.camp", string)

HASH_CAMP :: #load("../../stdlib/Hash.camp", string)

DEBUG_CAMP :: #load("../../stdlib/Debug.camp", string)

DEFAULT_CAMP :: #load("../../stdlib/Default.camp", string)


INTO_ITER_CAMP :: #load("../../stdlib/IntoIter.camp", string)

FROM_ITER_CAMP :: #load("../../stdlib/FromIter.camp", string)

FROM_CAMP :: #load("../../stdlib/From.camp", string)

TRY_FROM_CAMP :: #load("../../stdlib/TryFrom.camp", string)

CONSOLE_CAMP :: #load("../../stdlib/Console.camp", string)

THROW_CAMP :: #load("../../stdlib/Throw.camp", string)

FILE_CAMP :: #load("../../stdlib/File.camp", string)

ENV_CAMP :: #load("../../stdlib/Env.camp", string)

TIME_CAMP :: #load("../../stdlib/Time.camp", string)

RANDOM_CAMP :: #load("../../stdlib/Random.camp", string)

LOG_CAMP :: #load("../../stdlib/Log.camp", string)

PATH_CAMP :: #load("../../stdlib/Path.camp", string)

DURATION_CAMP :: #load("../../stdlib/Duration.camp", string)

FMT_CAMP :: #load("../../stdlib/Fmt.camp", string)

UUID_CAMP :: #load("../../stdlib/Uuid.camp", string)

URI_CAMP :: #load("../../stdlib/Uri.camp", string)

BASE64_CAMP :: #load("../../stdlib/Base64.camp", string)

JSON_CAMP :: #load("../../stdlib/Json.camp", string)

REGEX_CAMP :: #load("../../stdlib/Regex.camp", string)

UNIT_CAMP :: #load("../../stdlib/Unit.camp", string)

STDLIB_MODULES: []Stdlib_Module = []Stdlib_Module {
	{"Result", RESULT_CAMP, "stdlib/Result.camp"},
	{"ParseError", PARSE_ERROR_CAMP, "stdlib/ParseError.camp"},
	{"Bool", BOOL_CAMP, "stdlib/Bool.camp"},
	{"Str", STR_CAMP, "stdlib/Str.camp"},
	{"List", LIST_CAMP, "stdlib/List.camp"},
	{"Iter", ITER_CAMP, "stdlib/Iter.camp"},
	{"Map", MAP_CAMP, "stdlib/Map.camp"},
	{"Set", SET_CAMP, "stdlib/Set.camp"},
	{"Display", DISPLAY_CAMP, "stdlib/Display.camp"},
	{"Char", CHAR_CAMP, "stdlib/Char.camp"},
	{"Num.I64", NUM_I64_CAMP, "stdlib/Num/I64.camp"},
	{"Num.I32", NUM_I32_CAMP, "stdlib/Num/I32.camp"},
	{"Num.I16", NUM_I16_CAMP, "stdlib/Num/I16.camp"},
	{"Num.I8", NUM_I8_CAMP, "stdlib/Num/I8.camp"},
	{"Num.U64", NUM_U64_CAMP, "stdlib/Num/U64.camp"},
	{"Num.U32", NUM_U32_CAMP, "stdlib/Num/U32.camp"},
	{"Num.U16", NUM_U16_CAMP, "stdlib/Num/U16.camp"},
	{"Num.U8", NUM_U8_CAMP, "stdlib/Num/U8.camp"},
	{"Num.F64", NUM_F64_CAMP, "stdlib/Num/F64.camp"},
	{"Num.F32", NUM_F32_CAMP, "stdlib/Num/F32.camp"},
	{"Bytes", BYTES_CAMP, "stdlib/Bytes.camp"},
	{"Eq", EQ_CAMP, "stdlib/Eq.camp"},
	{"Ord", ORD_CAMP, "stdlib/Ord.camp"},
	{"Hash", HASH_CAMP, "stdlib/Hash.camp"},
	{"Debug", DEBUG_CAMP, "stdlib/Debug.camp"},
	{"Default", DEFAULT_CAMP, "stdlib/Default.camp"},
	{"IntoIter", INTO_ITER_CAMP, "stdlib/IntoIter.camp"},
	{"FromIter", FROM_ITER_CAMP, "stdlib/FromIter.camp"},
	{"From", FROM_CAMP, "stdlib/From.camp"},
	{"TryFrom", TRY_FROM_CAMP, "stdlib/TryFrom.camp"},
	{"Console", CONSOLE_CAMP, "stdlib/Console.camp"},
	{"Throw", THROW_CAMP, "stdlib/Throw.camp"},
	{"File", FILE_CAMP, "stdlib/File.camp"},
	{"Env", ENV_CAMP, "stdlib/Env.camp"},
	{"Time", TIME_CAMP, "stdlib/Time.camp"},
	{"Random", RANDOM_CAMP, "stdlib/Random.camp"},
	{"Log", LOG_CAMP, "stdlib/Log.camp"},
	{"Path", PATH_CAMP, "stdlib/Path.camp"},
	{"Duration", DURATION_CAMP, "stdlib/Duration.camp"},
	{"Fmt", FMT_CAMP, "stdlib/Fmt.camp"},
	{"Uuid", UUID_CAMP, "stdlib/Uuid.camp"},
	{"Json", JSON_CAMP, "stdlib/Json.camp"},
	{"Regex", REGEX_CAMP, "stdlib/Regex.camp"},
	{"Uri", URI_CAMP, "stdlib/Uri.camp"},
	{"Base64", BASE64_CAMP, "stdlib/Base64.camp"},
	{"Unit", UNIT_CAMP, "stdlib/Unit.camp"},
}

stdlib_lookup :: proc(name: string) -> (Stdlib_Module, bool) {
	for mod in STDLIB_MODULES {
		if mod.name == name {
			return mod, true
		}
	}
	return Stdlib_Module{}, false
}

stdlib_is_module :: proc(name: string) -> bool {
	_, ok := stdlib_lookup(name)
	return ok
}

