# Shared VM/JIT execution

Release order: [0.4](0.4.md). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Initial executor

The checked semantic graph feeds alternative backends under `src/5_codegen/`:
`llvm/` emits native code and `bytecode/` emits verified instructions. The VM
lives in `src/execution/`; execution is not a subsequent compilation phase.

`argi run --vm <directory>` lowers the checked global graph to typed bytecode
with source locations, verifies signatures/control flow/definite initialization,
and executes a bounded scalar/aggregate subset. Function and type identities remain
those of the retained global graph. See [usage](../docs/usage.md#experimental-bytecode-execution).

Next: extend partial initialization and error propagation, then define persistent sessions
and native calls before JIT or `#run`. Do not bypass safety to execute a larger subset.

Calls use an explicit VM frame stack, with one shared instruction budget and a
configurable depth limit independent of the host call stack. Each run resets its
execution state; returned aggregate values may be passed into the next run.

Local writes use a root slot plus typed field/index projections. Index operands
are evaluated once, and intermediate bounds checks retain native evaluation order.
The interpreter rebuilds only the modified aggregate path; immutable snapshots
preserve value-copy semantics. Safe references name run-local frame storage plus
captured projections. The
storage engine rejects dead frames and readonly writes; the ordinary frontend
continues to prove lexical lifetimes, aliasing, and storage-generation rules.
References cannot enter from external values or escape completed frames.

Cleanup lowers the frontend's selected operations and activation annotations to
ordinary branches and calls. Per-binding field/variant flags are initialized in
an entry prologue; moves disable source subtrees and initialization enables them.
Active payload guards precede their cleanup. Result-dependent consumption follows
selected output tags, including discarded results. No second ownership analysis
runs in the VM. Partial initialization through output references and native resources
remain outside the executor subset. Abort/quota failures do not execute user cleanup.

## Remaining decisions

- Extend storage to partial initialization and error propagation.
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
