# Compile-time execution and interactive tooling

Scheduling: [0.4](0.4.md). This note describes the investigation,
not an additional release requirement.

Explore whether compile-time execution, a REPL, JIT, and ahead-of-time builds
can share one execution model. This is an implementation direction, not a
language requirement.

- Evaluate a compact, typed, serializable executable IR as a common input to
  a compile-time interpreter and native codegen. A lightweight VM is one
  candidate for comptime and interactive execution; LLVM could consume the
  same semantics for JIT and ahead-of-time output. Reuse the existing
  semantic representation where possible before adding another IR.
- Investigate a persistent compiler session that caches function
  specializations by declaration, concrete type arguments, compile-time
  values, and dependencies. Generate them when first needed and invalidate
  entries when relevant code or inputs change.
- For a REPL, decide whether redefinition changes existing callers and how
  live values survive type changes. Recompilation alone cannot preserve
  incompatible program state.
- Measure the cost and benefits of shared execution machinery before
  committing to a VM or JIT architecture.
