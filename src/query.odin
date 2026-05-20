package camp

// Salsa-lite query layer.
//
// The pipeline is parse -> canonicalize -> typecheck. Each is a memoized
// query. The cache key for typecheck is the *canonical structural hash*
// (no spans, computed via structural_print_file). Source edits that don't
// change the canonical tree — whitespace, comments — re-run parse and
// canonicalize but reuse the cached typecheck output. This is the early-
// cutoff trick: typecheck's input is the value of canonicalize, not the
// version of the source.
//
// Scope (v0):
//   - Single-file. No imports, no module graph yet.
//   - In-memory only. No persistence across `camp` invocations.
//   - Unbounded cache (one entry per distinct canonical hash ever seen).
//   - Each cached entry owns its own Compilation_Context so cached
//     diagnostics stay valid until db_destroy.
//
// Not yet here (deliberate — separate PRs):
//   - Durability tiers (HIGH for stdlib, etc.)
//   - Multi-file dependency tracking
//   - The `lower` query (only needed for build, not check)
//   - Bounded LRU eviction

import "core:strings"

// ----------------------------------------------------------------------------
// Hashing helpers (FNV-1a, 64-bit)

FNV_OFFSET :: 0xcbf29ce484222325
FNV_PRIME  :: 0x00000100000001b3

hash_string :: proc(s: string) -> u64 {
	h: u64 = FNV_OFFSET
	for i in 0..<len(s) {
		h ~= u64(s[i])
		h *= FNV_PRIME
	}
	return h
}

// ----------------------------------------------------------------------------
// Cache entries

// Cached_TC owns the Compilation_Context that allocated its diagnostics.
// Keeping ctx alive keeps the diagnostic strings/labels valid for callers.
Cached_TC :: struct {
	canon_hash: u64,
	ctx:        ^Compilation_Context,
	store:      Type_Store,
	cfile:      CFile,
	// Snapshot of diagnostics at end of typecheck. Owned by ctx.
	diagnostics: [dynamic]Diagnostic,
}

// ----------------------------------------------------------------------------
// Query database

Query_DB :: struct {
	sources: map[string]string,

	// canon_hash -> typecheck result. Hits here mean two source edits
	// produced the same canonical tree (e.g. whitespace-only change).
	tc_cache: map[u64]^Cached_TC,

	// Stats. Useful for tests and for `camp stats` if we ever add one.
	parse_runs:        int,
	canonicalize_runs: int,
	typecheck_runs:    int,
	tc_cache_hits:     int,
}

db_init :: proc(db: ^Query_DB) {
	db.sources = make(map[string]string, 8)
	db.tc_cache = make(map[u64]^Cached_TC, 8)
}

db_destroy :: proc(db: ^Query_DB) {
	for _, entry in db.tc_cache {
		// context_destroy reaps the arena that holds entry.cfile, entry.store's
		// vars/bindings/etc., and all the strings inside entry.diagnostics.
		// We do NOT call type_store_destroy — its dynamic arrays were
		// allocated inside the arena and will be reaped along with it.
		context_destroy(entry.ctx)
		free(entry.ctx)
		// entry itself and the outer diagnostics slice were allocated with
		// the DB's (default) allocator, so they need explicit free/delete.
		delete(entry.diagnostics)
		free(entry)
	}
	delete(db.tc_cache)
	delete(db.sources)
}

// db_set_input registers (or replaces) source for a path. Does not invalidate
// caches — invalidation happens lazily during the next query call.
db_set_input :: proc(db: ^Query_DB, path: string, contents: string) {
	db.sources[path] = contents
}

// q_typecheck returns the typecheck result for a path. Spins up a fresh
// pipeline run, hashes the canonical tree, and either reuses the cached
// typecheck or runs it fresh and caches the result.
//
// Returns a pointer into the DB's cache. Valid until db_destroy.
q_typecheck :: proc(db: ^Query_DB, path: string) -> ^Cached_TC {
	source, ok := db.sources[path]
	if !ok {
		return nil
	}

	// Default (DB-owned) allocator. Used for the cache entry itself and the
	// outer diagnostics slice — anything we need to free in db_destroy.
	db_alloc := context.allocator

	// Per-run arena. Holds parse/canon/typecheck output. Reaped by
	// context_destroy when the entry is evicted from the cache.
	ctx := new(Compilation_Context)
	context_init(ctx)

	{
		context.allocator = ctx.allocator
		defer context.allocator = db_alloc

		file := Source_File{path = path, contents = source, id = 0}
		lexer: Lexer
		lexer_init(&lexer, file, &ctx.collector, &ctx.interner)

		parser: Parser
		parser_init(&parser, &lexer, &ctx.collector, &ctx.interner)
		surface := parser_parse_file(&parser)
		db.parse_runs += 1

		canon := canonicalize(surface, ctx)
		db.canonicalize_runs += 1

		canon_hash := hash_canon(canon)

		// Early-cutoff: same canonical tree as something we've seen before.
		if cached, hit := db.tc_cache[canon_hash]; hit {
			db.tc_cache_hits += 1
			context.allocator = db_alloc
			context_destroy(ctx)
			free(ctx)
			return cached
		}

		store: Type_Store
		type_store_init(&store, &ctx.interner, &ctx.collector)
		typecheck_file(canon, &store)
		db.typecheck_runs += 1

		// Switch back to DB allocator for the entry + the outer diagnostics
		// slice so db_destroy can free them cleanly. The inner Diagnostic
		// strings still point into ctx.arena — fine, ctx outlives the entry.
		context.allocator = db_alloc
		entry := new(Cached_TC)
		entry.canon_hash = canon_hash
		entry.ctx = ctx
		entry.store = store
		entry.cfile = canon
		entry.diagnostics = make([dynamic]Diagnostic, 0, len(ctx.collector.diagnostics))
		for d in ctx.collector.diagnostics {
			append(&entry.diagnostics, d)
		}
		db.tc_cache[canon_hash] = entry
		return entry
	}
}

// hash_canon computes a stable hash of the canonical tree.
// Uses the structural_print_file renderer from test_canonicalize.odin —
// the same renderer that anchors the cache-key acceptance test.
hash_canon :: proc(file: CFile) -> u64 {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	for decl in file.decls {
		structural_print_decl(&sb, decl)
		strings.write_string(&sb, "\n")
	}
	return hash_string(strings.to_string(sb))
}
