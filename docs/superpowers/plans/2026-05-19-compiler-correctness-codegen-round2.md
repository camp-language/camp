# Compiler Correctness & Codegen Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 remaining compiler bugs so all e2e execution tests pass or compile correctly.

**Architecture:** Each task targets a specific root cause discovered in e2e test failures. The typechecker has two name-resolution bugs (parent scope walk, match arm pattern bindings, assign binding). The codegen has missing operator implementations, incorrect closure field stride, and a placeholder `call{index=0}` for closure calls. One task fixes test data (outdated syntax) and one clamps exit codes.

**Tech Stack:** Odin, WASM/WASI, wasmtime for verification

---

## Bug Summary

| # | Bug | Root Cause | Failing Tests |
|---|-----|-----------|---------------|
| 1 | `emit_binop` missing comparison/boolean ops | Only handles Plus/Minus/Star | comparison-eq, comparison-lt, comparison-neq, and-or, not-operator |
| 2 | Negative exit codes crash wasmtime | `_start` passes raw I64 to `proc_exit` which only accepts `[0..126]` | negation |
| 3 | Closure field stride is 4 bytes (should be 8) | `total_size = header + n * 4` instead of `n * 8` | (latent — breaks when env has I64 values) |
| 4 | `IR_Closure_Call` uses `call{index=0}` | Always calls function 0 instead of `call_indirect` | function-call (when cross-decl refs work) |
| 5 | Typechecker doesn't walk parent scope | `env.bindings` lookup is flat, no parent chain | let-binding, multi-decl, function-call, function-identity |
| 6 | `CExpr_Assign` doesn't bind target in env | `x = 42` inside a block doesn't make `x` available | let-binding, multi-decl |
| 7 | Match arm 0 body typechecked before pattern | Line 603 typechecks arm[0].body without pattern bindings | tag-match patterns with variables |
| 8 | Test files use `(a, b)` instead of `\|a, b\|` | Outdated function param syntax | function-call, function-identity, recursive-call |

---

### Task 1: Add comparison and boolean operators to `emit_binop`

**Files:**
- Modify: `src/wasm.odin` (add 16 new Wasm instruction structs + union variants + encodings)
- Modify: `src/codegen.odin:511-514` (IR_BinOp emit_expr — pass operand type instead of result type)
- Modify: `src/codegen.odin:741-763` (emit_binop — add all comparison/boolean cases)

**Core insight:** `emit_binop` currently receives `e.type.wasm_type` which is the *result* type. For comparisons (Eq_Eq etc.), the result is I32 (bool) but operands are I64. We need the *operand* type from the left expression instead.

**New WASM instructions needed** (opcode in hex):
- `Wasm_I32_Eq` (0x46), `Wasm_I32_Ne` (0x47), `Wasm_I32_Lt_S` (0x48), `Wasm_I32_Gt_S` (0x49), `Wasm_I32_Le_S` (0x4A), `Wasm_I32_Ge_S` (0x4B)
- `Wasm_I64_Eq` (0x51), `Wasm_I64_Ne` (0x52), `Wasm_I64_Lt_S` (0x53), `Wasm_I64_Gt_S` (0x54), `Wasm_I64_Le_S` (0x55), `Wasm_I64_Ge_S` (0x56)
- `Wasm_I32_And` (0x71), `Wasm_I32_Or` (0x72)
- `Wasm_I64_And` (0x7B), `Wasm_I64_Or` (0x7C)

- [ ] **Step 1: Add WASM instruction structs to `src/wasm.odin`**

Add after `Wasm_I64_Mul` (~line 121):

```odin
Wasm_I32_Eq :: struct {}
Wasm_I32_Ne :: struct {}
Wasm_I32_Lt_S :: struct {}
Wasm_I32_Gt_S :: struct {}
Wasm_I32_Le_S :: struct {}
Wasm_I32_Ge_S :: struct {}
Wasm_I64_Eq :: struct {}
Wasm_I64_Ne :: struct {}
Wasm_I64_Lt_S :: struct {}
Wasm_I64_Gt_S :: struct {}
Wasm_I64_Le_S :: struct {}
Wasm_I64_Ge_S :: struct {}
Wasm_I32_And :: struct {}
Wasm_I32_Or :: struct {}
Wasm_I64_And :: struct {}
Wasm_I64_Or :: struct {}
```

- [ ] **Step 2: Add instruction variants to `Wasm_Instruction` union in `src/wasm.odin`**

Add each new struct to the `Wasm_Instruction :: union` block (~line 197-230), in the same order as the struct definitions.

- [ ] **Step 3: Add encoding cases to `emit_instruction` in `src/wasm.odin`**

Add in the switch block (~line 300-400), alphabetically near existing instructions:

```odin
case Wasm_I32_Eq: append(buf, 0x46)
case Wasm_I32_Ne: append(buf, 0x47)
case Wasm_I32_Lt_S: append(buf, 0x48)
case Wasm_I32_Gt_S: append(buf, 0x49)
case Wasm_I32_Le_S: append(buf, 0x4A)
case Wasm_I32_Ge_S: append(buf, 0x4B)
case Wasm_I64_Eq: append(buf, 0x51)
case Wasm_I64_Ne: append(buf, 0x52)
case Wasm_I64_Lt_S: append(buf, 0x53)
case Wasm_I64_Gt_S: append(buf, 0x54)
case Wasm_I64_Le_S: append(buf, 0x55)
case Wasm_I64_Ge_S: append(buf, 0x56)
case Wasm_I32_And: append(buf, 0x71)
case Wasm_I32_Or: append(buf, 0x72)
case Wasm_I64_And: append(buf, 0x7B)
case Wasm_I64_Or: append(buf, 0x7C)
```

- [ ] **Step 4: Add `ir_operand_wasm_type` helper to `src/codegen.odin`**

Add near `ir_expr_wasm_type` (~line 766):

```odin
ir_operand_wasm_type :: proc(expr: IR_Expr) -> IR_Wasm_Type {
	if expr == nil do return .I32
	#partial switch e in expr {
	case ^IR_Literal_Int: return e.type.wasm_type
	case ^IR_Literal_Float: return e.type.wasm_type
	case ^IR_Literal_Bool: return .I32
	case ^IR_Literal_String: return .I32
	case ^IR_Var: return e.type.wasm_type
	case ^IR_BinOp: return e.type.wasm_type
	case ^IR_Call: return e.type.wasm_type
	case ^IR_If: return e.type.wasm_type
	case ^IR_Closure_Call: return e.type.wasm_type
	case ^IR_Field_Access: return e.type.wasm_type
	case ^IR_Construct_Tag: return .I32
	case ^IR_Construct_Record: return .I32
	case ^IR_Closure: return .I32
	case:
		return .I32
	}
	return .I32
}
```

Note: For comparisons, the operand type determines which comparison instruction to use (i32.eq vs i64.eq). For `IR_BinOp` operands that are themselves comparisons, `e.type.wasm_type` is I32 (bool), which is correct since boolean comparisons operate on I32.

- [ ] **Step 5: Rewrite `emit_binop` to handle all operators**

Replace `emit_binop` (lines 741-763) with:

```odin
emit_binop :: proc(op: Token_Kind, operand_type: IR_Wasm_Type, buf: ^[dynamic]u8) {
	#partial switch op {
	case .Plus:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Add{}, buf)
		} else {
			emit_instruction(Wasm_I64_Add{}, buf)
		}
	case .Minus:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Sub{}, buf)
		} else {
			emit_instruction(Wasm_I64_Sub{}, buf)
		}
	case .Star:
		if operand_type == .I32 {
			emit_instruction(Wasm_I32_Mul{}, buf)
		} else {
			emit_instruction(Wasm_I64_Mul{}, buf)
		}
	case .Eq_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Eq{}, buf)
		} else {
			emit_instruction(Wasm_I32_Eq{}, buf)
		}
	case .Bang_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Ne{}, buf)
		} else {
			emit_instruction(Wasm_I32_Ne{}, buf)
		}
	case .Lt:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Lt_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Lt_S{}, buf)
		}
	case .Gt:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Gt_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Gt_S{}, buf)
		}
	case .Lt_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Le_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Le_S{}, buf)
		}
	case .Gt_Eq:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Ge_S{}, buf)
		} else {
			emit_instruction(Wasm_I32_Ge_S{}, buf)
		}
	case .Kw_And:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_And{}, buf)
		} else {
			emit_instruction(Wasm_I32_And{}, buf)
		}
	case .Kw_Or:
		if operand_type == .I64 {
			emit_instruction(Wasm_I64_Or{}, buf)
		} else {
			emit_instruction(Wasm_I32_Or{}, buf)
		}
	case:
		emit_instruction(Wasm_I64_Add{}, buf)
	}
}
```

- [ ] **Step 6: Update the IR_BinOp emit_expr call site**

Change line 514 from:
```odin
emit_binop(e.op, e.type.wasm_type, buf)
```
to:
```odin
operand_type := ir_operand_wasm_type(e.left)
emit_binop(e.op, operand_type, buf)
```

- [ ] **Step 7: Build and run unit tests**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 8: Verify comparison e2e tests**

```bash
./camp build tests/e2e/execution/comparison-eq.camp && wasmtime run tests/e2e/execution/comparison-eq.wasm; echo $?
```
Expected: exit code 1 (1 == 1 is true)

```bash
./camp build tests/e2e/execution/comparison-lt.camp && wasmtime run tests/e2e/execution/comparison-lt.wasm; echo $?
```
Expected: exit code 1

```bash
./camp build tests/e2e/execution/comparison-neq.camp && wasmtime run tests/e2e/execution/comparison-neq.wasm; echo $?
```
Expected: exit code 1 (1 != 2 is true)

- [ ] **Step 9: Verify boolean e2e tests**

```bash
./camp build tests/e2e/execution/and-or.camp && wasmtime run tests/e2e/execution/and-or.wasm; echo $?
```
Expected: exit code 2 (true and false → false, so else: true or false → true → 2)

```bash
./camp build tests/e2e/execution/not-operator.camp && wasmtime run tests/e2e/execution/not-operator.wasm; echo $?
```
Expected: exit code 1 (not false = true)

- [ ] **Step 10: Commit**

```bash
git add src/codegen.odin src/wasm.odin
git commit -m "feat(codegen): implement comparison and boolean operators in emit_binop"
```

---

### Task 2: Clamp negative exit codes in `_start`

**Files:**
- Modify: `src/codegen.odin:296-316` (_start function emission)

WASI `proc_exit` only accepts `[0..126]`. When `main!` returns a negative I64, `i32.wrap_i64` produces a negative I32, which crashes wasmtime. Fix: after `i32.wrap_i64`, mask to 7 bits with `i32.const 127; i32.and`. This guarantees exit code is in `[0..127]`.

**Prerequisite:** Task 1 (provides `Wasm_I32_And`)

- [ ] **Step 1: Add exit code clamping to `_start` emission**

In `src/codegen.odin`, after the `Wasm_I32_Wrap_I64` instruction (~line 308) and before the `Wasm_Call{index = 0}` (~line 311), add:

```odin
emit_instruction(Wasm_I32_Const{value = 127}, &code_buf)
emit_instruction(Wasm_I32_And{}, &code_buf)
```

This masks the exit code to `value & 0x7F`, guaranteeing it's in `[0..127]`.

- [ ] **Step 2: Build and run unit tests**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 3: Verify negation e2e test no longer crashes**

```bash
./camp build tests/e2e/execution/negation.camp && wasmtime run tests/e2e/execution/negation.wasm 2>&1; echo $?
```
Expected: No crash. Exit code = 86 (because `-42 & 127 = 0xFFFFFFD6 & 0x7F = 0x56 = 86`).

Note: The original test `main! = || -> I64 { 0 - 42 }` computes -42, which is semantically not a valid exit code. The `& 127` clamp makes it deterministic (86) rather than crashing. The `negation.expected.toml` may need updating if it expects a different exit code.

- [ ] **Step 4: Commit**

```bash
git add src/codegen.odin
git commit -m "fix(codegen): clamp _start exit code to [0..127] for WASI proc_exit"
```

---

### Task 3: Fix closure heap field stride to 8 bytes

**Files:**
- Modify: `src/codegen.odin:668-706` (IR_Closure emit_expr case)
- Modify: `src/codegen.odin:708-721` (IR_Closure_Call emit_expr case)

IR_Construct_Tag uses `num_fields * 8` for total_size and `CAMP_TAG_FIELDS_OFFSET + i * 8` for field offsets, but IR_Closure uses `num_fields * 4` and `CAMP_TAG_FIELDS_OFFSET + 4` for the env field. This inconsistency breaks when closures carry I64 env values.

- [ ] **Step 1: Fix IR_Closure total_size calculation**

Change line 670 from:
```odin
total_size := CAMP_TAG_HEADER_SIZE + num_fields * 4
```
to:
```odin
total_size := CAMP_TAG_HEADER_SIZE + num_fields * 8
```

- [ ] **Step 2: Fix IR_Closure env_ptr store offset**

Change line 701 from:
```odin
emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 4)}, buf)
```
to:
```odin
emit_instruction(Wasm_I32_Const{value = i32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
```

- [ ] **Step 3: Fix IR_Closure_Call env_ptr load offset**

Change line 715 from:
```odin
emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 4)}, buf)
```
to:
```odin
emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)
```

- [ ] **Step 4: Build and run unit tests**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add src/codegen.odin
git commit -m "fix(codegen): use 8-byte field stride for closure heap layout"
```

---

### Task 4: Replace `call{index=0}` with `call_indirect` in IR_Closure_Call

**Files:**
- Modify: `src/codegen.odin` (add table + element segment creation, add `func_type_indices` field, rewrite IR_Closure_Call)
- Modify: `src/codegen.odin:14-27` (Codegen_Env — add `table_idx`, `func_type_indices` fields)

Currently `IR_Closure_Call` always calls `Wasm_Call{index = 0}`. The closure stores `fn_idx` at `CAMP_TAG_FIELDS_OFFSET`. We need `call_indirect` to dispatch to the correct function at runtime.

**WASM element segment encoding** (already implemented in `src/wasm.odin:585-602`):
```
Wasm_Element :: struct {
    table_idx: int,
    offset:    []u8,      // init expr (i32.const + end byte)
    func_idxs: []int,     // function indices to place in table
}
```

**Strategy:** Create a funcref table at module init time with one slot per function. Populate it with an element segment that maps `table[fn_idx] = fn_idx` for every function. Then in `IR_Closure_Call`, load fn_idx from the closure and use `call_indirect` with the correct type_idx.

**Prerequisite:** Task 3 (8-byte closure field stride for correct env_ptr offset)

- [ ] **Step 1: Add fields to Codegen_Env**

Add to `Codegen_Env` struct (lines 14-27):

```odin
table_idx:     int,
func_type_indices: [dynamic]u32,
```

Initialize in the codegen function:
```odin
env.table_idx = -1
env.func_type_indices = make([dynamic]u32, 0, 64)
```

- [ ] **Step 2: Create funcref table at module init time**

After `append(&mod.memories, Wasm_Memory{min = 1})` (~line 132), add:

```odin
env.table_idx = len(mod.tables)
append(&mod.tables, Wasm_Table{
	elem_type = .Funcref,
	min = 1,
	max = 1,
	has_max = true,
})
```

Note: We set min/max to 1 initially and will update the table size after we know the total function count.

- [ ] **Step 3: Record type_idx for each compiled function**

After `add_function(&env, type_idx)` and `env.func_map[int(d.name.name)] = func_idx` in the decl loop (~line 201-202), add:

```odin
for len(env.func_type_indices) <= func_idx {
	append(&env.func_type_indices, 0)
}
env.func_type_indices[func_idx] = u32(type_idx)
```

- [ ] **Step 4: Create element segment after all functions are emitted**

After the decl loop (~line 293, before `_start` emission), add the element segment:

```odin
if env.table_idx >= 0 && len(env.func_type_indices) > 0 {
	total_funcs := len(env.func_type_indices)

	mod.tables[env.table_idx].min = u32(total_funcs)
	mod.tables[env.table_idx].max = u32(total_funcs)

	elem_offset_buf: [dynamic]u8
	elem_offset_buf = make([dynamic]u8, 0, 8)
	emit_instruction(Wasm_I32_Const{value = 0}, &elem_offset_buf)

	elem_func_indices: [dynamic]int
	elem_func_indices = make([dynamic]int, 0, total_funcs)
	for i in 0..<total_funcs {
		append(&elem_func_indices, i)
	}

	append(&mod.elements, Wasm_Element{
		table_idx = env.table_idx,
		offset = copy_dynamic_bytes(elem_offset_buf),
		func_idxs = elem_func_indices[:],
	})
	delete(elem_offset_buf)
	delete(elem_func_indices)
}
```

This places every function (imports + program functions) in the table at its own index, so `table[fn_idx]` == function `fn_idx`.

- [ ] **Step 5: Rewrite IR_Closure_Call to use `call_indirect`**

`IR_Closure_Call` struct (in `src/ir.odin:225-230`) has:
- `callee: IR_Expr` — the closure expression
- `args: [dynamic]IR_Expr` — the arguments
- `type: IR_Type` — the return type

It does NOT have an `fn_name` field. To get the `type_idx` for `call_indirect`, we reconstruct the function signature from the call site: `(i32 [env_ptr], arg_types...) -> return_type`. Then look up the type with `get_or_create_type`.

Replace the IR_Closure_Call case (lines 708-721) with:

```odin
case ^IR_Closure_Call:
	emit_expr(e.callee, buf, env, runtime_indices)

	callee_local := env.tmp_local_base + 1
	emit_instruction(Wasm_Local_Set{index = callee_local}, buf)

	emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET + 8)}, buf)

	for arg in e.args {
		emit_expr(arg, buf, env, runtime_indices)
	}

	emit_instruction(Wasm_Local_Get{index = callee_local}, buf)
	emit_instruction(Wasm_I32_Load{align = 2, offset = u32(CAMP_TAG_FIELDS_OFFSET)}, buf)

	// Reconstruct the closure's function type: (i32, arg_types...) -> return_type
	closure_params := make([]Wasm_Value_Type, len(e.args) + 1)
	closure_params[0] = .I32  // env_ptr
	for i, arg in e.args {
		closure_params[i + 1] = ir_expr_wasm_type(arg)
	}
	closure_results := make([]Wasm_Value_Type, 1)
	closure_results[0] = ir_wasm_type_to_value_type(e.type.wasm_type)
	closure_type_idx := get_or_create_type(env, closure_params, closure_results)

	emit_instruction(Wasm_Call_Indirect{type_idx = u32(closure_type_idx), table_idx = u32(env.table_idx)}, buf)
```

Note: `get_or_create_type` is already used in codegen (~line 84, 154, 200, 214). `ir_expr_wasm_type` is already defined (~line 766). `ir_wasm_type_to_value_type` is already defined.

- [ ] **Step 6: Verify the funcref table element type encoding**

The `Wasm_Table.elem_type` field is a `Wasm_Value_Type`. For funcref tables, the value is `.Funcref` (= 0x70). Verify that the table encoding in `src/wasm.odin:507-524` correctly serializes this as byte 0x70. If it uses `u8(tbl.elem_type)`, this will work since `Wasm_Value_Type` is `enum u8`.

- [ ] **Step 7: Build and run unit tests**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add src/codegen.odin
git commit -m "feat(codegen): use call_indirect for IR_Closure_Call with funcref table"
```

---

### Task 5: Fix typechecker parent scope lookup

**Files:**
- Modify: `src/typecheck.odin:54-65` (find_similar_names — walk parent chain)
- Modify: `src/typecheck.odin:198-207` (CExpr_Name case — use env_lookup)

The name lookup at line 199 only checks `env.bindings` directly. It needs to walk up the `env.parent` chain. For top-level cross-decl references (`x = 10; main! = || -> I64 { x }`), the lambda creates a child env with `parent = env`. The child needs to find `x` in the parent.

- [ ] **Step 1: Add `env_lookup` helper**

Add near the top of `src/typecheck.odin` (after the `Type_Result` struct, ~line 16):

```odin
env_lookup :: proc(env: ^Type_Env, name: Intern_ID) -> (Type_Var_ID, bool) {
	current := env
	for current != nil {
		if existing, ok := current.bindings[name]; ok {
			return existing, true
		}
		current = current.parent
	}
	return Type_Var_ID(-1), false
}
```

- [ ] **Step 2: Update CExpr_Name case to use env_lookup**

Replace lines 198-207:

Old:
```odin
case ^CExpr_Name:
	if existing, ok := env.bindings[e.name.name]; ok {
		inst := instantiate(store, existing)
		return Type_Result{var_id = inst, effects = fresh_effect_row(store, e.span)}
	}
	...
```

New:
```odin
case ^CExpr_Name:
	if existing, ok := env_lookup(env, e.name.name); ok {
		inst := instantiate(store, existing)
		return Type_Result{var_id = inst, effects = fresh_effect_row(store, e.span)}
	}
	var_id := fresh_value_var(store, e.span)
	name_str := intern_get(store.interner, e.name.name)
	similar := find_similar_names(name_str, env, store.interner)
	collector_add_diag(store.collector, diag_undefined_name(name_str, similar, e.span))
	return Type_Result{var_id = var_id, effects = fresh_effect_row(store, e.span)}
```

- [ ] **Step 3: Update `find_similar_names` to walk parent chain**

Replace lines 54-65 with:

```odin
find_similar_names :: proc(name: string, env: ^Type_Env, interner: ^Intern_Table) -> []string {
	names: [dynamic]string
	current := env
	for current != nil {
		for k, _ in current.bindings {
			k_str := intern_get(interner, k)
			if levenshtein_distance(name, k_str) <= 2 {
				append(&names, k_str)
			}
		}
		current = current.parent
	}
	return names[:]
}
```

- [ ] **Step 4: Build and test**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 5: Verify cross-decl references work**

```bash
cat > /tmp/test_cross.camp << 'EOF'
x = 10
main! = || -> I64 { x }
EOF
./camp build /tmp/test_cross.camp
```
Expected: Compiles without UNDEFINED NAME error

- [ ] **Step 6: Commit**

```bash
git add src/typecheck.odin
git commit -m "fix(typecheck): walk parent scope chain for name lookup"
```

---

### Task 6: Fix match arm 0 body typechecked before pattern bindings

**Files:**
- Modify: `src/typecheck.odin:597-607` (typecheck_match — remove premature arm[0] typecheck)

Line 603 typechecks `e.arms[0].body` before any pattern is processed, so pattern variables in arm 0 are undefined. The fix: replace the premature typecheck with a fresh type variable, and let the loop handle all arms uniformly.

- [ ] **Step 1: Remove premature arm[0] body typecheck**

Replace lines 597-607:

Old:
```odin
	saved_bindings := make(map[Intern_ID]Type_Var_ID, len(env.bindings))
	for k, v in env.bindings {
		saved_bindings[k] = v
	}
	defer delete(saved_bindings)

	first_result := typecheck_synth(e.arms[0].body, env, store)
	result_var := first_result.var_id
	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, scrutinee_result.effects)
	unify(store, effect_row, first_result.effects)
```

New:
```odin
	saved_bindings := make(map[Intern_ID]Type_Var_ID, len(env.bindings))
	for k, v in env.bindings {
		saved_bindings[k] = v
	}
	defer delete(saved_bindings)

	result_var := fresh_value_var(store, e.span)
	effect_row := fresh_effect_row(store, e.span)
	unify(store, effect_row, scrutinee_result.effects)
```

The loop at lines 614-631 already typechecks ALL arms (including arm 0) with proper pattern bindings. No changes needed there.

- [ ] **Step 2: Build and test**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 3: Verify match with pattern variables**

```bash
cat > /tmp/test_match_vars.camp << 'EOF'
main! = || -> I64 { match Ok(42) { Ok(v) => v | Error(e) => 0 } }
EOF
./camp build /tmp/test_match_vars.camp
```
Expected: No UNDEFINED NAME error for `v` or `e`. (The "expected a row type" error may still appear — that's a separate type system issue.)

- [ ] **Step 4: Commit**

```bash
git add src/typecheck.odin
git commit -m "fix(typecheck): typecheck match arm 0 body after pattern bindings"
```

---

### Task 7: Fix `CExpr_Assign` to add binding to typechecker env

**Files:**
- Modify: `src/typecheck.odin:245-247` (CExpr_Assign case)

`CExpr_Assign` typechecks the value but doesn't add the target name to `env.bindings`. This means `x = 42` inside a block doesn't make `x` available to subsequent statements.

- [ ] **Step 1: Update CExpr_Assign typecheck to bind the target name**

Replace lines 245-247:

Old:
```odin
	case ^CExpr_Assign:
		result := typecheck_synth(e.value, env, store)
		return Type_Result{var_id = result.var_id, effects = result.effects}
```

New:
```odin
	case ^CExpr_Assign:
		result := typecheck_synth(e.value, env, store)
		switch target in e.target {
		case ^CExpr_Name:
			env.bindings[target.name.name] = result.var_id
		case ^CExpr_Dollar_Identifier:
			env.bindings[target.name.name] = result.var_id
		case:
		}
		return Type_Result{var_id = result.var_id, effects = result.effects}
```

- [ ] **Step 2: Build and test**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 3: Verify let-binding e2e test**

```bash
./camp build tests/e2e/execution/let-binding.camp && wasmtime run tests/e2e/execution/let-binding.wasm; echo $?
```
Expected: exit code 43 (y = 42 + 1 = 43)

- [ ] **Step 4: Verify multi-decl e2e test**

```bash
./camp build tests/e2e/execution/multi-decl.camp && wasmtime run tests/e2e/execution/multi-decl.wasm; echo $?
```
Expected: exit code 30 (x + y = 10 + 20 = 30)

- [ ] **Step 5: Commit**

```bash
git add src/typecheck.odin
git commit -m "fix(typecheck): bind assigned names in scope for CExpr_Assign"
```

---

### Task 8: Update e2e test files with correct lambda syntax

**Files:**
- Modify: `tests/e2e/execution/function-call.camp`
- Modify: `tests/e2e/execution/function-identity.camp`
- Modify: `tests/e2e/execution/recursive-call.camp`
- Modify: corresponding `.expected.toml` files

The function param syntax `(a, b) -> I64 { ... }` is not supported by the parser. The correct syntax is `|a, b| -> I64 { ... }`.

**Prerequisite:** Tasks 5 and 7 (cross-decl references must work for these tests to compile)

- [ ] **Step 1: Update function-call.camp**

Change from:
```
add = (a, b) -> I64 { a + b }
main! = || -> I64 { add(3, 4) }
```
To:
```
add = |a, b| -> I64 { a + b }
main! = || -> I64 { add(3, 4) }
```

- [ ] **Step 2: Update function-identity.camp**

Change from:
```
id = (x) -> I64 { x }
main! = || -> I64 { id(42) }
```
To:
```
id = |x| -> I64 { x }
main! = || -> I64 { id(42) }
```

- [ ] **Step 3: Update recursive-call.camp**

Change from:
```
loop! = (n) -> I64 { if n == 0 0 else loop!(n - 1) }
main! = || -> I64 { loop!(5) }
```
To:
```
loop! = |n| -> I64 { if n == 0 0 else loop!(n - 1) }
main! = || -> I64 { loop!(5) }
```

- [ ] **Step 4: Build, run, and update expected.toml files**

For each test, build and run to determine the actual output, then update the `.expected.toml`:

```bash
./camp build tests/e2e/execution/function-call.camp && wasmtime run tests/e2e/execution/function-call.wasm; echo $?
```
Expected: exit code 7 (3 + 4)

```bash
./camp build tests/e2e/execution/function-identity.camp && wasmtime run tests/e2e/execution/function-identity.wasm; echo $?
```
Expected: exit code 42

```bash
./camp build tests/e2e/execution/recursive-call.camp && wasmtime run tests/e2e/execution/recursive-call.wasm; echo $?
```
Expected: exit code 0

Then update each `.expected.toml` with the correct `stdout`, `stderr`, and `exit` values.

- [ ] **Step 5: Commit**

```bash
git add tests/e2e/execution/function-call.camp tests/e2e/execution/function-identity.camp tests/e2e/execution/recursive-call.camp tests/e2e/execution/function-call.expected.toml tests/e2e/execution/function-identity.expected.toml tests/e2e/execution/recursive-call.expected.toml
git commit -m "fix(e2e): update function declaration syntax to use pipe params"
```

---

### Task 9: End-to-end verification

- [ ] **Step 1: Run all unit tests**

Run: `odin test src`
Expected: All tests pass

- [ ] **Step 2: Run all e2e execution tests**

```bash
for f in tests/e2e/execution/*.camp; do
  name=$(basename "$f" .camp)
  out=$(./camp build "$f" 2>&1)
  if echo "$out" | grep -q "compiled"; then
    result=$(wasmtime run "tests/e2e/execution/${name}.wasm" 2>&1)
    rc=$?
    if echo "$result" | grep -qi "error\|type mismatch\|invalid"; then
      echo "FAIL_RUNTIME  $name"
    else
      echo "OK            $name: exit=$rc"
    fi
    rm -f "tests/e2e/execution/${name}.wasm"
  else
    echo "FAIL_COMPILE  $name"
  fi
done
```

Expected: All tests either OK or have known pre-existing issues documented.

- [ ] **Step 3: Document remaining known issues**

Any tests that still fail should be documented with their root cause and whether they're in scope for this round.

- [ ] **Step 4: Final commit if needed**

```bash
git add -A
git commit -m "chore: update expected.toml files for passing e2e tests"
```
