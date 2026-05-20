package camp

import "core:testing"
import "core:fmt"

@(test)
test_query_cold_run :: proc(t: ^testing.T) {
	db: Query_DB
	db_init(&db)
	defer db_destroy(&db)

	db_set_input(&db, "a.camp", "x = 42")
	r := q_typecheck(&db, "a.camp")

	testing.expect(t, r != nil)
	testing.expect(t, db.parse_runs == 1)
	testing.expect(t, db.canonicalize_runs == 1)
	testing.expect(t, db.typecheck_runs == 1)
	testing.expect(t, db.tc_cache_hits == 0)
}

@(test)
test_query_whitespace_edit_hits_early_cutoff :: proc(t: ^testing.T) {
	// Edit only changes whitespace. Canonical hash is the same, so the
	// cached typecheck is reused — typecheck does not re-run.
	db: Query_DB
	db_init(&db)
	defer db_destroy(&db)

	db_set_input(&db, "a.camp", "x = 42")
	first := q_typecheck(&db, "a.camp")

	db_set_input(&db, "a.camp", "x    =\n  42")
	second := q_typecheck(&db, "a.camp")

	testing.expect(t, first == second, "cached entry pointer should be reused on hash match")
	testing.expect(t, db.parse_runs == 2)
	testing.expect(t, db.canonicalize_runs == 2)
	testing.expect(t, db.typecheck_runs == 1, fmt.tprintf("typecheck should run once, ran %d", db.typecheck_runs))
	testing.expect(t, db.tc_cache_hits == 1, fmt.tprintf("expected 1 cache hit, got %d", db.tc_cache_hits))
}

@(test)
test_query_semantic_edit_invalidates :: proc(t: ^testing.T) {
	db: Query_DB
	db_init(&db)
	defer db_destroy(&db)

	db_set_input(&db, "a.camp", "x = 42")
	first := q_typecheck(&db, "a.camp")

	db_set_input(&db, "a.camp", "x = 43") // value differs => canon hash differs
	second := q_typecheck(&db, "a.camp")

	testing.expect(t, first != second, "different canonical content must produce different cache entries")
	testing.expect(t, db.typecheck_runs == 2, fmt.tprintf("typecheck should run twice, ran %d", db.typecheck_runs))
	testing.expect(t, db.tc_cache_hits == 0)
}

@(test)
test_query_revert_to_prior_hits_cache :: proc(t: ^testing.T) {
	// Editing back to a previously-seen canonical form should reuse the
	// original cached entry — the cache is keyed by canon hash, not by time.
	db: Query_DB
	db_init(&db)
	defer db_destroy(&db)

	db_set_input(&db, "a.camp", "x = 42")
	first := q_typecheck(&db, "a.camp")

	db_set_input(&db, "a.camp", "x = 43")
	q_typecheck(&db, "a.camp")

	db_set_input(&db, "a.camp", "x = 42") // back to original
	third := q_typecheck(&db, "a.camp")

	testing.expect(t, first == third, "reverting to a prior canonical form should reuse its cached typecheck")
	testing.expect(t, db.typecheck_runs == 2, fmt.tprintf("typecheck should run twice (42 then 43), ran %d", db.typecheck_runs))
	testing.expect(t, db.tc_cache_hits == 1)
}

@(test)
test_query_diagnostics_survive_invalidation :: proc(t: ^testing.T) {
	// The Cached_TC's diagnostics are owned by the ctx field; as long as the
	// cache holds the entry, the strings inside diagnostics remain valid.
	db: Query_DB
	db_init(&db)
	defer db_destroy(&db)

	db_set_input(&db, "a.camp", "a = 1 + true") // type error
	first := q_typecheck(&db, "a.camp")
	first_msg := ""
	for d in first.diagnostics {
		if d.category == .Error {
			first_msg = d.message
			break
		}
	}
	testing.expect(t, first_msg != "", "expected an error diagnostic")

	// Edit to something different, then back. The original entry must still
	// be alive in the cache and its message string must still be readable.
	db_set_input(&db, "a.camp", "x = 1")
	q_typecheck(&db, "a.camp")

	db_set_input(&db, "a.camp", "a = 1 + true")
	revisited := q_typecheck(&db, "a.camp")
	testing.expect(t, revisited == first)
	testing.expect(t, len(revisited.diagnostics) == len(first.diagnostics))
	for d in revisited.diagnostics {
		if d.category == .Error {
			testing.expect(t, d.message == first_msg, "message should still be readable")
			break
		}
	}
}
