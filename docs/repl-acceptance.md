# REPL release acceptance

The REPL is supported for the scope below. It uses ordinary semantic analysis,
Safety and verified bytecode execution. Stability does not imply unrestricted
native execution or complete LLVM parity.

## Supported scope and regression coverage

| Guarantee | Regression coverage |
| --- | --- |
| Persistent values, definitions, types and contracts | `src/execution/interactive.zig`: controller, definitions, contract definitions, introspection and specialization tests |
| Text and owning collections | Native/VM fixtures `text/29_string_view_split`, `collections/157_unified_hash_map`, `165_unified_hash_set`, `166_unified_priority_queue` |
| Borrowing, partial initialization and cleanup across commands | Interactive presented references, expression owners, vacant records, owning arrays and incomplete choice payload tests; Safety aliasing and duplicate-cleanup rejections |
| Compile-time execution and imports | Interactive staged run, anonymous entries, computed imports, source diagnostics and conditional selection tests |
| Rejection is atomic; execution is not | Interactive rejected input, poisoned reset, cancellation, failed reset allocation and accepted-state retry tests |
| Bounded resources and interactive latency | `src/execution_benchmark.zig`; measured budgets and longer rejection control below |
| Terminal and piped input | `repl_input.zig`, `repl.zig`, POSIX terminal probes and native Windows ConPTY acceptance |

The map example in [usage](usage.md#persistent-repl) also passes
through piped CLI input, producing the documented `0`, `()` and `..some` results.

Internal tests run on Unix and Windows. Windows program validation includes
collections, text, I/O and system fixtures. Terminal probes use POSIX
pseudoterminals and a Windows ConPTY child (`tests/native/windows/repl_console.c`).
The Windows workflow builds that probe and checks Unicode input, scalar editing,
history replay, cancellation and multiline continuation against the installed
compiler. Separate children exercise clean `:quit` and Ctrl-D exits.
Native validation [41030576835](https://github.com/endikallanomatxin/argi/actions/runs/41030576835)
passes on Linux x86-64/ARM64 and macOS x86-64/ARM64, including internal tests,
program fixtures, terminal probes and extracted distributions. Linux consumers
also pass without installed LLVM. Windows validation
[41022201658](https://github.com/endikallanomatxin/argi/actions/runs/41022201658)
passes Unicode editing/history, continuation, runtime Ctrl-C with inherited
ignore state, reset recovery and both clean exit paths, plus internal/core tests.
Optional Python validation
[41022201696](https://github.com/endikallanomatxin/argi/actions/runs/41022201696)
passes all ten platform/Python combinations.

Long input uses a horizontal viewport rather than terminal wrapping. Linux PTY
acceptance passes with a 24-column function definition, a 12-column Unicode edit
and a resize back to 80 columns. Scalar-boundary and lexical-context unit tests
cover the same renderer. The viewport conservatively reserves two cells per
non-ASCII scalar; actual cursor placement remains the terminal's responsibility.
This is not a grapheme-width or identical-font-rendering guarantee.

The local 0.4.0 candidate distribution also passes checksum verification and the
extracted-package smoke test outside the checkout. Generated project tooling and
the cat, echo, word-count, tree and weighted-regression consumers pass in Debug
and release. Package creation checks that the installed binary reports the
manifest version; a stale 0.3.0 installation is rejected before packaging.
Logs: `.zig-cache/release-candidate-{package,smoke}.log` and
`.zig-cache/release-version-mismatch.log`.

The complete real-core ReleaseSafe preparation sweep passes all 32,653
allocation failures and 545 resize failures in native run `41030576835`.
Four consecutive ranges preserve exhaustive coverage while bounding each CI step.
Accepted-state rollback, cleanup and retry are checked independently in the
interactive and REPL tests. Log: `.zig-cache/repl-ci-complete.log`.

## Stability contract

- Ordinary semantic analysis and Safety apply before publication. Rejected input
  leaves accepted values, definitions and resources usable.
- Published execution may have observable effects before a trap or cancellation.
  The context becomes poisoned and requires reset; effects are not rolled back.
  Poisoned teardown releases VM backing without replaying unsafe destructors.
- Healthy reset and exit execute checked cleanup. A preparation failure preserves
  live owners and permits retry. Numbered results intentionally remain live.
- The prelude supplies explicit output, allocator and tracer assumptions. It does
  not grant unrestricted System or arbitrary native execution.
- Unsupported constructs must fail with a source diagnostic, rather than silently
  falling back to native execution or different language rules.

## Reference resource budgets

Use isolated Linux x86-64 ReleaseSafe runs as a reproducible reference, rather
than a latency promise for every host. For 1,000-command prelude sessions covering
calls, definitions, retained resources and rejected inputs:

- Peak tracked backing, including checked close, must stay below 512 MiB.
- Final-window submission p95 must stay below 100 ms; checked close below 5 s.
- Rejections may retain at most 4 MiB of reusable capacity after setup, with no
  growth in semantic graph payload or live VM backing.
- Healthy close must succeed and destruction must release every tracked byte.

The 2026-10-30 reference rerun enforces the 512 MiB ceiling and satisfies these
thresholds: largest peak 286.640 MiB, p95 23.415 ms and close 780.065 ms.
All four workloads complete checked close and release all tracked backing.
The 10,000-command rejection control also passes: retained backing stays at
144.593 MiB from command 1,000 onward, graph payload and live VM backing remain
unchanged, and final-window p95 is 4.448 ms. Checked close succeeds in 11.419 ms
and destruction releases every tracked byte.
See [measurements and the corrected teardown failure](compiler-performance.md#checked-resource-session-teardown).
Tracked backing includes allocator slabs; it is not process RSS or user-owned
payload alone. Execution instruction, call-depth and value-cell quotas remain
separate limits with their documented trap/reset behavior.

## Supported execution boundaries

Current executable boundaries, checked against `bytecode/lower.zig` and
`bytecode/verify.zig`:

| Boundary | Current rejection |
| --- | --- |
| Runtime owning writes | Indexed replacement and replacement through runtime references require cleanup evidence not yet transported by these paths |
| Native calls | Indirect calls are rejected; foreign calls require an explicit scalar host binding |
| Memory representation | Acquired references and byte reinterpretation require supported numeric layouts and checked allocation receipts where owning storage needs them |
| Global/captured storage | Unresolved storage outside local/session bindings is rejected; this is not a general closure or owning-global execution facility |
| Compile-time execution | Acquired metadata preparation is rejected in compile-time mode |
| Compile-time entry dependencies | `once` functions cannot execute in compile-time mode; the ordinary REPL execution mode is a separate boundary |
| Function exits | Explicit return expressions are rejected by VM lowering; output bindings and checked early exits remain the ordinary supported forms |
| Targets | Verification currently requires the native host target |

Additional structural limits are explicit: storage projections have at most 64
components, and acquired numeric storage must have a representable layout.
Lowering also checks its own invariants (typed expressions, completed record
arguments and checked helper evidence). Those failures must not be advertised as
intentional restrictions on otherwise supported source programs.

These are restrictions to exercise with diagnostics, not reasons to exclude an
entire library when its ordinary checked operations already work. In particular,
supported collection owners use checked acquisition and cleanup paths.

Full LLVM parity, JIT, closures and unrestricted native FFI are outside this
release's supported scope. Untaken branches in reachable bodies may still require
unsupported lowering. Cross-target compile-time semantics and dependency tracking
for external compile-time reads remain separate compiler work.
