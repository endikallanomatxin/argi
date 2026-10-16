# Shared VM/JIT execution

Release order: [0.4](0.4.md). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Initial executor

`argi run --vm <directory>` lowers the checked global graph to typed bytecode
with source locations, verifies signatures/control flow/definite initialization,
and executes a bounded scalar/record subset. Function and type identities remain
those of the retained global graph. See [usage](../docs/usage.md#experimental-bytecode-execution).

Next: extend values/storage and ordinary cleanup, then define persistent sessions
and native calls before JIT or `#run`. Do not bypass safety to execute a larger subset.

## Remaining decisions

- Extend frames and aggregates to references, arrays, choices, and cleanup.
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

## Reference

Zig's `Sema.zig` evaluates comptime bodies during semantic analysis, with
explicit comptime allocations and an evaluation branch quota. The local study
uses the checksum-verified source archive for
[0.18.0-dev.253+16d31ceed](https://ziglang.org/builds/zig-0.18.0-dev.253+16d31ceed.tar.xz)
under ignored `references/zig/`. Argi keeps its planned reusable executor
separate from contract resolution; this is not Zig's execution architecture.
