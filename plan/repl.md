# REPL — remaining release gates

Ship a non-experimental REPL for the documented VM subset. No JIT, full native
parity or general compiler redesign is required.

1. Finish the real-core allocation/resize sweep. The reproduced 4,000-byte leak
   at allocation 28,909 is fixed and passes independently; complete coverage is
   still running. Keep accepted-state rollback and retry checks passing.
2. Finish reference-budget validation: rerun the existing 1,000-command workloads
   with 512 MiB and the longer rejection control. Measurements and budgets exist;
   the 1,000-owner cleanup OOM is fixed. Require clean checked teardown.
3. Validate the final candidate together: internal/program suites and native/VM
   cases, Linux/macOS/Windows CI and optional Python/package consumers. Resolve
   demonstrated failures, including Darwin PTY resizing after its ioctl fix.
   Then finalize usage/release notes and remove the REPL
   experimental label. Do not publish the release yet.

Scope, guarantees, exclusions and evidence: [REPL acceptance](../docs/repl-acceptance.md).
Measurements: [compiler performance](../docs/compiler-performance.md).

Existing coverage includes persistent values/owners/references, imports,
generics/contracts, partial initialization, cleanup, cross-unit virtual calls,
`#run`/`#if`, traps and reset. Do not keep these as open-ended feature tasks or
expand acceptance without a concrete gap.

Compiler optimizations and broader execution support remain separate follow-ups
in [compiler.md](compiler.md); closures and JIT are deferred.
