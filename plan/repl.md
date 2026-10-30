# REPL — remaining release gates

Ship a non-experimental REPL for the documented VM subset. No JIT, full native
parity or general compiler redesign is required.

1. Finish the complete real-core allocation sweep in CI. Focused late-allocation
   checks and all 545 resize failures pass after the leak fixes; complete
   allocation coverage is still running. Preserve accepted-state rollback/retry.
2. Validate the final candidate together: internal/program suites and native/VM
   cases, Linux/macOS/Windows CI and optional Python/package consumers. Resolve
   demonstrated failures. Then finalize usage/release notes and remove the REPL
   experimental label. Do not publish the release yet.

Scope, guarantees, exclusions and evidence: [REPL acceptance](../docs/repl-acceptance.md).
Measurements: [compiler performance](../docs/compiler-performance.md).

Reference budgets pass for four 1,000-command workloads and 10,000 rejected
submissions under 512 MiB, including checked teardown and complete deallocation.

Existing coverage includes persistent values/owners/references, imports,
generics/contracts, partial initialization, cleanup, cross-unit virtual calls,
`#run`/`#if`, traps and reset. Do not keep these as open-ended feature tasks or
expand acceptance without a concrete gap.

Compiler optimizations and broader execution support remain separate follow-ups
in [compiler.md](compiler.md); closures and JIT are deferred.
