# REPL release acceptance

This is an evidence map, not a claim that stabilization is complete. The REPL
remains experimental until the open gates in [the plan](../plan/repl.md) close.
Use the existing internal and program suites; do not maintain a second runner.

## Supported scope to validate

| Guarantee | Existing checks | Remaining acceptance work |
| --- | --- | --- |
| Persistent values, definitions, types and contracts | `src/execution/interactive.zig`: controller, definitions, contract definitions, introspection and specialization tests | Run together against the release candidate |
| Text and owning collections | Native/VM fixtures `text/29_string_view_split`, `collections/157_unified_hash_map`, `165_unified_hash_set`, `166_unified_priority_queue` | Audit unsupported operations used by everyday consumers |
| Borrowing, partial initialization and cleanup across commands | Interactive presented references, expression owners, vacant records, owning arrays and incomplete choice payload tests | Retain aliasing and duplicate-cleanup rejection coverage |
| Compile-time execution and imports | Interactive staged run, anonymous entries, computed imports and conditional selection tests | Verify source diagnostics and accepted-state preservation together |
| Rejection is atomic; execution is not | Interactive rejected input, poisoned reset, cancellation and reset-allocation tests | Exhaustive resource-bearing semantic preparation and accepted-state retry |
| Bounded resources and interactive latency | `src/execution_benchmark.zig` and `docs/compiler-performance.md` | Refresh growing-session measurements and set acceptance budgets |
| Terminal and piped input | `repl_input.zig`, `repl.zig` and `tests/terminal_probe.zig` | Unicode display widths, cursor behavior and explicit platform coverage |

Internal tests run on Unix and Windows. Windows program validation includes
collections, text, I/O and system fixtures. The real-terminal probes currently
use POSIX pseudoterminals; passing transport tests alone does not demonstrate
Windows console behavior. Record actual workflow results for the final candidate,
not merely the presence of workflow definitions.
The cursor save/restore sequences used by the editor (`CSI s` / `CSI u`) are
[documented by Windows Console](https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences#cursor-positioning).
That protocol support does not replace an interactive Windows acceptance probe.
Windows terminal setup now saves both console modes and code pages, selects
UTF-8 for byte I/O, and restores the saved state after normal exit or partial
setup failure. Host-independent tests inject each setup failure; the real API
path also compiles for x86-64 Windows. Native console Unicode acceptance remains
open, including the actual byte-input behavior of supported Windows versions.

Local preflight on Linux x86-64 (2026-10-29) passed the five collection/text
fixtures listed above, including `collections/149_owned_ordering`, plus execution
fixtures `02_floating_point_vm`, `14_integer_boundaries_vm`,
`119_allocation_cleanup` and `138_comptime_transient_expression_defaults`.
Each passed its native assertions and VM assertions with matching stdout and
the expected exit status. This used the existing installed compiler; repeat
against the final candidate, including its rebuilt editor and bundled libraries.

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

## Exclusions to publish

Current executable boundaries, checked against `bytecode/lower.zig` and
`bytecode/verify.zig`:

| Boundary | Current rejection |
| --- | --- |
| Runtime owning writes | Indexed replacement and replacement through runtime references require cleanup evidence not yet transported by these paths |
| Native calls | Indirect calls are rejected; foreign calls require an explicit scalar host binding |
| Memory representation | Acquired references and byte reinterpretation require supported numeric layouts and checked allocation receipts where owning storage needs them |
| Global/captured storage | Unresolved storage outside local/session bindings is rejected; this is not a general closure or owning-global execution facility |
| Compile-time execution | Acquired metadata preparation is rejected in compile-time mode |
| Targets | Verification currently requires the native host target |

These are restrictions to exercise with diagnostics, not reasons to exclude an
entire library when its ordinary checked operations already work. In particular,
supported collection owners use checked acquisition and cleanup paths.

Full LLVM parity, JIT, closures and unrestricted native FFI are not prerequisites.
Inventory actual bytecode rejections before finalizing the supported subset,
including indirect calls, owning globals, acquired layouts and indirect owning
writes. Untaken branches in reachable bodies may still require unsupported
lowering. Cross-target compile-time semantics and dependency tracking for external
compile-time reads remain separate compiler work.

Do not remove the experimental label until the scope above has executable
acceptance evidence, measured resource limits, documented exclusions and passing
release-candidate CI. Terminal width policy must acknowledge terminal-specific
rendering rather than promise identical glyph presentation everywhere.
