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
