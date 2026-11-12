# Incomplete write destinations (open soundness counterexample)

Compile only. Do not execute this program: `other.reference` can retain a
reference to `temporary` after its storage has ended.

The abstract target set of `target` contains `slot` plus an unknown alternative
returned by `Source.get`. A weak update of `slot.reference` is necessary, but
cannot describe the write to `other.reference`. Clearing `slot.reference`
afterward must not discharge obligations for that uncovered destination.

The current checker accepts this reduction, including with explicit incomplete
target facts. It demonstrates a remaining gap, not supported safe behavior.
See [reference target coverage](../../reference_target_coverage.md).

## Additional reductions

- `aliased_inputs/` has no `Virtual` or unknown-producing call. Both inputs name
  one slot at the call site; the body reads its expired reference through the
  second name before repairing through the first. This is now rejected and
  retained as negative concurrency fixture 235X.
- `caller_read/` omits the slot read from the helper. The read occurs in its
  caller after the helper returns, so a body-only check cannot close the gap.

These directories are compile-only reductions, never safe executable examples.
The original and `caller_read/` remain accepted soundness counterexamples.
The safe counterparts are concurrency fixtures 232, 233 and 234; see the
[write-conservation gates](../../reference_target_coverage.md#write-conservation-gates).
