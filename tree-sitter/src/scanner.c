/*
 * tree-sitter-camp external scanner for interpolated strings.
 *
 * Handles string interpolation with `${expr}` syntax, supporting:
 *   - Regular strings:    "Hello ${name}!"
 *   - Raw strings:        r"C:\${dir}"     (\ is literal except for \$)
 *   - Triple-quoted:      """multi\nline ${x}!"""
 *   - Escape sequences:   \\, \n, \r, \t, \", \$ (in non-raw strings)
 *   - Nested braces:      "${record.{field}}"
 *
 * The scanner tracks:
 *   - Whether we are inside a string and which kind
 *   - Brace depth for interpolation (to find the matching `}` of `${}`)
 */

#include "tree_sitter/parser.h"
#include "tree_sitter/alloc.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* ---------------------------------------------------------------------------
 * Token type IDs — order matches the `externals` array in grammar.js
 * ------------------------------------------------------------------------- */
enum TokenType {
  STRING_START,          // 0 = _string_start
  STRING_START_BSLASH,   // 1 = _string_start_bslash
  STRING_CONTENT,        // 2 = _string_content
  INTERPOLATION_START,   // 3 = _interpolation_start
  INTERPOLATION_END,     // 4 = _interpolation_end
  STRING_END,            // 5 = _string_end
};

/* ---------------------------------------------------------------------------
 * Scanner state — serialized/deserialized across tree-sitter calls
 * ------------------------------------------------------------------------- */
typedef struct {
  bool in_string;    // currently inside a string
  bool is_raw;       // r"..." — backslash is literal, except \$ escapes
  bool is_triple;    // """...""" — newlines allowed
  uint32_t depth;    // brace depth: 0 = string content, >0 = inside ${}
} Scanner;

/* ---------------------------------------------------------------------------
 * Allocate a new scanner instance.
 * ------------------------------------------------------------------------- */
void *tree_sitter_camp_external_scanner_create(void) {
  Scanner *s = (Scanner *)ts_malloc(sizeof(Scanner));
  s->in_string = false;
  s->is_raw = false;
  s->is_triple = false;
  s->depth = 0;
  return s;
}

/* ---------------------------------------------------------------------------
 * Free the scanner.
 * ------------------------------------------------------------------------- */
void tree_sitter_camp_external_scanner_destroy(void *payload) {
  ts_free(payload);
}

/* ---------------------------------------------------------------------------
 * Serialize scanner state for tree-sitter's backtracking.
 * State fits in 7 bytes: 3 bools + 4-byte uint32 for depth.
 * ------------------------------------------------------------------------- */
unsigned tree_sitter_camp_external_scanner_serialize(void *payload, char *buffer) {
  Scanner *s = (Scanner *)payload;
  buffer[0] = (char)s->in_string;
  buffer[1] = (char)s->is_raw;
  buffer[2] = (char)s->is_triple;
  ((uint32_t *)(buffer + 3))[0] = s->depth;
  return 7;
}

/* ---------------------------------------------------------------------------
 * Deserialize scanner state.
 * ------------------------------------------------------------------------- */
void tree_sitter_camp_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Scanner *s = (Scanner *)payload;
  if (length == 0) {
    s->in_string = false;
    s->is_raw = false;
    s->is_triple = false;
    s->depth = 0;
    return;
  }
  if (length != 7) return;
  s->in_string = (bool)buffer[0];
  s->is_raw = (bool)buffer[1];
  s->is_triple = (bool)buffer[2];
  s->depth = ((const uint32_t *)(buffer + 3))[0];
}

/* ---------------------------------------------------------------------------
 * Inline helpers.
 * ------------------------------------------------------------------------- */
static inline void advance(TSLexer *lexer) { lexer->advance(lexer, false); }
static inline void skip(TSLexer *lexer)    { lexer->advance(lexer, true); }

/* ---------------------------------------------------------------------------
 * Skip whitespace characters (consumed, not emitted as tokens).
 * ------------------------------------------------------------------------- */
static void skip_whitespace(TSLexer *lexer) {
  for (;;) {
    switch (lexer->lookahead) {
      case ' ': case '\t': case '\r': case '\n': skip(lexer); continue;
      default: return;
    }
  }
}

/* ===========================================================================
 * Scan helpers for string start tokens.
 *
 * These are called from the main `scan` function when the corresponding
 * `valid_symbols` entries are set.
 * =========================================================================== */

/* ---------------------------------------------------------------------------
 * Try to match `r"`  (raw string start).
 * Advances past both chars on success.
 * ------------------------------------------------------------------------- */
static bool scan_start_r(Scanner *s, TSLexer *lexer) {
  if (lexer->lookahead != 'r') return false;
  advance(lexer);
  if (lexer->lookahead == '"') {
    advance(lexer);
    s->in_string = true;
    s->is_raw = true;
    s->is_triple = false;
    s->depth = 0;
    lexer->result_symbol = STRING_START_BSLASH;
    return true;
  }
  // Not r" — parser only asks for this when it expects it,
  // so failing here is fine (parser backtracks).
  return false;
}

/* ---------------------------------------------------------------------------
 * Try to match `"""` (triple-quoted string start).
 * Advances past all three quotes on success.
 * ------------------------------------------------------------------------- */
static bool scan_start_triple(Scanner *s, TSLexer *lexer) {
  if (lexer->lookahead != '"') return false;
  advance(lexer);
  if (lexer->lookahead != '"') return false; // single ", not """
  advance(lexer);
  if (lexer->lookahead != '"') return false; // two quotes, not three
  advance(lexer);
  s->in_string = true;
  s->is_raw = false;
  s->is_triple = true;
  s->depth = 0;
  lexer->result_symbol = STRING_START_BSLASH;
  return true;
}

/* ---------------------------------------------------------------------------
 * Try to match `"`  (regular string start).
 * Advances past the quote on success.
 * ------------------------------------------------------------------------- */
static bool scan_start_regular(Scanner *s, TSLexer *lexer) {
  if (lexer->lookahead != '"') return false;
  advance(lexer);
  s->in_string = true;
  s->is_raw = false;
  s->is_triple = false;
  s->depth = 0;
  lexer->result_symbol = STRING_START;
  return true;
}

/* ===========================================================================
 * String body scanning — called when one of STRING_CONTENT,
 * INTERPOLATION_START, or STRING_END is valid.
 *
 * Tries, in order:
 *   1. Interpolation close `}`   (defer to separate handler)
 *   2. String end `"` / `"""`     (emit STRING_END)
 *   3. Interpolation start `${`   (emit INTERPOLATION_START, push depth)
 *   4. String content             (emit STRING_CONTENT)
 * =========================================================================== */
static bool scan_string_body(Scanner *s, TSLexer *lexer, const bool *valid_symbols) {
  if (!s->in_string) return false;

  /* ---- 1. Interpolation close (handled elsewhere) ---- */
  if (s->depth > 0 && lexer->lookahead == '}') {
    return false; // let scan_interpolation_end handle it
  }

  /* ---- 2. String end ---- */
  if (lexer->lookahead == '"') {
    if (s->is_triple) {
      // Check for """ without consuming the opening quote
      TSLexer snap = *lexer;
      advance(lexer);
      if (lexer->lookahead == '"') {
        advance(lexer);
        if (lexer->lookahead == '"') {
          advance(lexer);
          lexer->result_symbol = STRING_END;
          s->in_string = false;
          s->is_triple = false;
          return true;
        }
      }
      // Not """ — restore the lexer position and include " as content
      *lexer = snap;
    } else {
      // Regular or raw string: " closes it
      advance(lexer);
      lexer->result_symbol = STRING_END;
      s->in_string = false;
      s->is_raw = false;
      return true;
    }
  }

  /* ---- 3. Interpolation start ${ ---- */
  bool consumed_dollar = false;
  if (lexer->lookahead == '$') {
    advance(lexer);
    if (lexer->lookahead == '{') {
      advance(lexer);
      s->depth = 1;
      lexer->result_symbol = INTERPOLATION_START;
      return true;
    }
    // Single $ not followed by { — include $ as content
    lexer->mark_end(lexer);
    consumed_dollar = true;
  }

  /* ---- 4. String content ---- */
  lexer->mark_end(lexer);
  bool advanced = consumed_dollar;

  for (;;) {
    int32_t c = lexer->lookahead;

    /* End of input */
    if (c == 0) {
      if (advanced) break;
      return false;
    }

    /* Newline in non-triple string is illegal */
    if (c == '\n' && !s->is_triple) {
      if (advanced) break;
      return false;
    }

    /* Escape sequences (non-raw strings) */
    if (c == '\\' && !s->is_raw) {
      advance(lexer);
      if (lexer->lookahead == 0) break;
      advance(lexer);
      advanced = true;
      lexer->mark_end(lexer);
      continue;
    }

    /* \$ in raw strings: literal $, no interpolation */
    if (c == '\\' && s->is_raw) {
      advance(lexer);
      if (lexer->lookahead == '$') {
        advance(lexer);
        advanced = true;
        lexer->mark_end(lexer);
        continue;
      }
      if (lexer->lookahead == 0) break;
      // Backslash is literal in raw strings; don't advance past it yet
      advanced = true;
      lexer->mark_end(lexer);
      continue;
    }

    /* $ — might start interpolation, stop content here */
    if (c == '$') {
      if (advanced) break; // emit content up to $
      // No prior content — try ${ (this catches the case where
      // the previous check saw $ but followed by non-{)
      advance(lexer);
      if (lexer->lookahead == '{') {
        advance(lexer);
        s->depth = 1;
        lexer->result_symbol = INTERPOLATION_START;
        return true;
      }
      // Still not ${ — include $ in content
      advanced = true;
      lexer->mark_end(lexer);
      continue;
    }

    /* " — might close the string */
    if (c == '"') {
      if (advanced) break; // emit content up to "
      // No content yet — if triple, check for """ below;
      // otherwise let the caller handle STRING_END on the next call.
      if (s->is_triple) {
        // Try """ from scratch (no prior content)
        TSLexer snap = *lexer;
        advance(lexer);
        if (lexer->lookahead == '"') {
          advance(lexer);
          if (lexer->lookahead == '"') {
            advance(lexer);
            lexer->result_symbol = STRING_END;
            s->in_string = false;
            s->is_triple = false;
            return true;
          }
        }
        *lexer = snap;
        // Single " in triple → content
        advance(lexer);
        advanced = true;
        lexer->mark_end(lexer);
        continue;
      }
      // Regular/raw string with no content before " — defer to STRING_END
      return false;
    }

    /* Regular character — consume */
    advance(lexer);
    advanced = true;
    lexer->mark_end(lexer);
  }

  if (advanced) {
    lexer->result_symbol = STRING_CONTENT;
    return true;
  }

  return false;
}

/* ===========================================================================
 * Interpolation end scanning.
 *
 * Called when INTERPOLATION_END is valid.  Tracks brace depth to find the
 * matching `}` that closes the current interpolation.  Braces that belong
 * to the expression (blocks, records) are counted and skipped.
 *
 * Returns true when the matching `}` is found and INTERPOLATION_END emitted.
 * =========================================================================== */
static bool scan_interpolation_end(Scanner *s, TSLexer *lexer, const bool *valid_symbols) {
  if (!s->in_string || s->depth == 0) return false;

  skip_whitespace(lexer);

  int32_t c = lexer->lookahead;

  if (c == '}') {
    if (s->depth == 1) {
      advance(lexer);
      s->depth = 0;
      lexer->result_symbol = INTERPOLATION_END;
      return true;
    }
    // } at depth > 1 — part of the expression
    s->depth--;
    return false; // let internal lexer handle as anon_sym_RBRACE
  }

  if (c == '{') {
    // Part of the expression inside ${}
    s->depth++;
    return false; // let internal lexer handle as anon_sym_LBRACE
  }

  return false; // not what we're looking for
}

/* ===========================================================================
 * Main scan entry point.
 *
 * Called by tree-sitter on every token where at least one external token
 * is valid.  The `valid_symbols` array is indexed by TokenType and tells
 * us which external tokens the parser can accept in the current state.
 *
 * Dispatch order:
 *   1. String start tokens (r", """, ")  — when not inside a string
 *   2. Interpolation end }               — when at brace depth > 0
 *   3. String body tokens                 — content, ${, or closing "
 * =========================================================================== */
bool tree_sitter_camp_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols) {
  Scanner *s = (Scanner *)payload;

  skip_whitespace(lexer);

  /* ---- String start (only valid when NOT inside a string) ---- */
  if (!s->in_string) {
    if (valid_symbols[STRING_START_BSLASH]) {
      if (scan_start_r(s, lexer)) return true;
    }
    if (valid_symbols[STRING_START_BSLASH]) {
      if (scan_start_triple(s, lexer)) return true;
    }
    if (valid_symbols[STRING_START]) {
      if (scan_start_regular(s, lexer)) return true;
    }
    return false;
  }

  /* ---- Interpolation end (inside string, parser expects }) ---- */
  if (valid_symbols[INTERPOLATION_END]) {
    if (scan_interpolation_end(s, lexer, valid_symbols)) {
      return true;
    }
  }

  /* ---- String body (content, ${, or ") ---- */
  if (valid_symbols[STRING_CONTENT] || valid_symbols[INTERPOLATION_START] || valid_symbols[STRING_END]) {
    if (scan_string_body(s, lexer, valid_symbols)) {
      return true;
    }
  }

  return false;
}
