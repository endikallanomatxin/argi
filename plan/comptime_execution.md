# Shared VM/JIT execution

Release order: [0.4](0.4.md). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Decisions before implementation

- Initial executable subset and diagnostics for unsupported constructs.
- Typed bytecode, verification, frames, aggregates, references, and source maps.
- Shared VM/native calling convention, output storage, errors, and cleanup.
- LLVM JIT integration, symbol resolution, and supported host/C signatures.
- Session persistence, redefinition, failed submissions, reset, and exit.
- Comptime capabilities, frozen results, target behavior, and cache dependencies.
- Instruction/recursion, memory, and time limits; cancellation at safe points.

## Constraints

Lower checked semantics; do not reimplement language resolution in the evaluator.
Keep function identity independent of its executor. Native code must outlive its
references, including across redefinition and failed submissions.

Rejected submissions must not publish partial definitions. Executed I/O cannot
be rolled back. Retained values need session-owned storage and ordinary lifetime
checks; initially reject redefinitions that invalidate live dependencies.

Comptime must not inherit runtime System/FFI permissions. Freeze supported values
into compiler-owned constants; reject escaped evaluator references/native handles.
Host execution must preserve target widths/layouts or reject unsupported operations.

## Validation

Compare VM, JIT, mixed calls, and AOT for aggregates, generics, virtual calls,
errors, cleanup, and output lifetimes. Force executor modes in tests. Measure
cold/repeated evaluation before selecting automatic promotion thresholds.
