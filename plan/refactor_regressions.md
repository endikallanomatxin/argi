# Compact graph refactor: regression handoff

Checkpoint: 2026-09-09, branch `compact-semantic-graph-chatgpt`.
The session started at `6d90348`; the branch was fast-forwarded to the published
`97ac0c5` before implementation. The changes described below are local changes
on top of that commit. The refactor is **not ready to merge**.

## Changes in this checkpoint

- Infer implicit generic type parameters from current argument node types,
  including pointer children and named generic container arguments. Do not use
  the call aggregate's potentially stale field types as inference evidence.
- Reject conflicting repeated type parameters. Respect named/positional call
  arguments and module visibility during candidate lookup.
- Resolve nested template calls with the same overload selection and implicit
  inference used for ordinary deferred calls. Complete their call inputs.
- Score generic signatures before instantiating the selected body. Signature
  probes discard temporary graph entries; otherwise each fixed-point retry can
  introduce fresh generic identities and prevent termination.
- Roll back appended graph pools and instance statistics when generic body
  instantiation fails. Previously a reserved instance could survive with an
  incomplete body and be incorrectly reused on the next retry.
- Refine inferred local binding types from their instantiated initializers and
  use those types for binding-use nodes. Publish recursively instantiated nodes,
  bindings, blocks and bodies only after recursive work has completed.
- Permit a mutable pointer argument where a read-only pointer to the same child
  type is expected; reject the reverse permission change.
- Correct the ExternalRef size-budget test to 44 bytes, accounting for both
  optional qualifier and optional generic-argument ranges.
- Preserve abstract type identity through call compatibility and use abstract
  implementation checks when a concrete pointer is passed to an abstract
  parameter.
- Lower and instantiate template matches, contextual choice literals and
  empty type initializers. Resolve ordinary `is(.value = x, .variant = ..tag)`
  calls as tag comparisons so payload-bearing variants can be tested without
  constructing their payload.
- Materialize generic type fields before their bodies inspect those fields.
- Avoid caching requirement instances across speculative graph rollback;
  rolled-back IDs can otherwise alias unrelated types on the next fixed-point
  pass.

Implementation comments live beside the corresponding code in
`src/4_semantics/global_semantic_generic_functions.zig`.

## Validation

- `zig build` passes with local Zig 0.16.0.
- Latest internal tests: **110 passed, 1 crash, 111 total**. The remaining crash
  is the existing downstream LSP null-result assumption described below.
- Three new regression tests pass: nested implicit inference through a local
  pointer alias (including a discarded overload with an unresolved body),
  conflicting repeated parameters, and repeated failed instantiation without
  publishing a reusable partial instance.
- The existing LSP protocol definition test still crashes when it assumes the
  returned `result` is an object but receives null after semantizing fails.
- The final full-suite run was stopped after the internal results were available,
  at the user's request to end the session. The complete executable suite is not green. An earlier full run in this session
  reported 31 passed / 627 failed; it is not a clean final before/after comparison
  because compiler development overlapped that run. Do not present the internal
  count as the result of the whole suite.
- The minimal module still fails during semantizing, before codegen; no new
  executable or LLVM IR was validated for this checkpoint.

Reproduce using the current test path (the old `tests/00_minimal_main` path does
not exist):

```sh
env ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-global-cache zig build
./zig-out/bin/argi build tests/feature_tests/basics/01_minimal_main
env ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-global-cache zig build test
```

## Observed remaining blockers, in suggested order

1. **Finish ordinary system initializers.** Allocator and strings now resolve
   completely. Trusted drops of a type without an explicit destructor lower to
   a no-op, matching the retired semantizer. Contextual structural literals
   participate in overload scoring, and deferred `move`/arithmetic nodes refine
   after their bindings become concrete. The next group is `core/system`:
   `size_of(.type = UIntNative)` still contains an unresolved type identifier in
   a value expression, and ordinary `CAllocator()`, `Terminal(...)`,
   `Arguments()` and related type initializers need the non-template
   initialization path.
2. **Complete virtual codegen.** All three allocator `to_virtual` calls now
   resolve by validating every abstract requirement and recording one concrete
   function per vtable slot. The semantic graph contains real method and safety
   registries. `src/5_codegen/global_codegen.zig` still returns
   `NotYetImplemented` for both `virtualize` and `virtual_call`; semantizing
   alone will not finish this.
3. **Core formatting correction.** `format_unsigned_decimal_into_u64` and
   `format_signed_decimal_into_i64` incorrectly called their 32-bit helper
   names. They now select the existing overloaded 64-bit helper, avoiding an
   unsafe implicit narrowing conversion in semantizing.
4. **Inference coverage.** This checkpoint handles type parameters, pointers,
   and named generic container arguments. It does not implement inference of
   comptime integers, dependent array lengths, or all other template type forms.
   Add focused positive/negative tests before extending those cases.
5. **Module-local generic materialization.** An attempted end-to-end fixture with
   a local `Box#(.t: Int32)` variable failed ModuleSG completeness verification
   with `IncompleteGenericMaterialization`, before GlobalSema. This independent
   issue was observed but not repaired; the retained inference fixture uses a
   scalar pointee to isolate the intended regression.
6. **LSP and diagnostics.** The definition test's null result is downstream of
   unresolved core semantizing. Merely avoiding the union access in the test
   would not restore definitions. Pending-call diagnostics currently print only
   the first eight unresolved operations and discard nested candidate failure
   reasons; preserve a useful selected-candidate cause and source location when
   improving this next.

Once the minimum passes, validate its LLVM IR and executable, then run the full
suite to distinguish shared-core failures from feature-specific regressions.
Do not merge to develop/main or claim refactor parity from internal tests alone.
