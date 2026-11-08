# Compiler follow-ups

REPL guarantees and acceptance evidence are recorded in
[the acceptance notes](../docs/repl-acceptance.md). Prioritize demonstrated
correctness or cost issues in the follow-ups below.

## Next: self-hosting prerequisites

Use the [self-hosted CLI prototype](../argi-compiler/README.md) as the next
sequential workload. Investigate the following in order before expanding its
frontend. These are targeted prerequisites and design checks, not a claim that
all five require new language features. Arenas, owning collections, nominal
IDs, contracts and structural reflection already exist.

1. **Reference dependencies through owning collections.** Reproduce storing,
   moving and extracting records/choices that borrow source text, using both
   DynamicArray and HashMap. Opaque extraction currently retains conservative
   storage-level dependencies instead of reconstructing exact dependencies of
   stored references. Identify valid compiler operations this rejects and improve
   precision where demonstrated. Accept independent source-backed values when
   justified; keep rejection of source destruction, arena reset and genuinely
   stale collection loans. Preserve cleanup on extraction and failure. See
   [the documented limitation](../description/34_safety_model.md#physical-validity-of-references).
2. **Computed compile-time metadata.** Extend non-integer generic value arguments
   beyond literal trees and forwarded parameters to checked computed expressions,
   calls and projections; support omitted record-field defaults in metadata
   literals. Preserve immutable value identity, type checks, privacy, staged
   ownership and REPL/cache behavior. Cover generated token/operation metadata,
   equal computed specializations, invalid references and native/VM agreement.
   See [immutable value parameters](../description/50_comptime.md#immutable-value-parameters).
3. **AST and type-graph storage.** Start with nominal NodeId/TypeId values and
   short-lived loans. A small choice-based AST with indexed children was compiled
   and executed during investigation. DynamicArray growth invalidates outstanding
   element references even without reallocation; a stale-loan probe was rejected
   as specified. Do not weaken that contract. Evaluate a stable-storage collection
   only if real compiler operations need it; this is initially library/design
   work. See [dynamic-array lifetime rules](../description/161_lists.md).
4. **Module boundaries.** Sketch source, syntax, semantic graph and phase modules
   with shared types below their consumers. Imports currently reject cycles;
   files in one directory share a namespace. Test whether that organization is
   sufficient before proposing cyclic imports. See
   [directory modules](../description/02_modules.md#directory-modules).
5. **LLVM boundary and compiler scale.** No LLVM binding library was found in
   core/more during investigation. Exercise the existing FFI with a minimal LLVM
   module, verification, code emission and linking; validate the actual required
   opaque handles, signatures and callbacks before identifying language gaps.
   Track compile time, peak memory and specialization growth as the Argi workload
   grows, separating clean frontend, cached frontend and backend costs. Neither
   full LLVM compatibility nor compiler-scale performance has been established.

The first implementation focus is reference-bearing collection behavior, followed
by computed compile-time metadata. Keep investigation fixtures and conclusions
with each change. Concurrency is a separate workstream; a sequential compiler
must not depend on completing it. Do not postpone implementation for hypothetical
features when IDs, ordinary contracts or existing library facilities suffice.

## Resolution

- Replace temporary resolver communication state with explicit results. Preserve
  useful diagnostics across speculative rollback, including readonly generic
  virtual conversions.
- Reduce remaining unresolved-binding inference and Safety sweeps in
  specialization workloads. Retained expression/reference propagation now skips
  certified prefixes and revisits older entities when their facts change;
  ownership still needs operands outside execution reachability.

## Safety

- Extend conditional storage effects through stored results, indirect outputs
  and loops, preserving intervening writes and caller identities.
- Extend hidden retention/replacement and grouped opaque mappings through output
  fields when a consumer needs them.
- Represent hidden storage and cleanup identities before virtualizing Resizable.
- Extend post-call virtual capture proofs to conditional/loop initialization,
  mutable receiver aliases, nested virtual receivers and active structural
  fallback cleanup. Straight-line definite initialization uses explicit capture
  phases and planned post-state identities; unproved ordering stays rejected.

## Performance validation

- Extend compilation and allocation-runtime benchmarks to larger consumers.
  Compare equivalent virtual capability setup with fixed compiler optimization,
  frontend workers and cache policy. Alternate samples and record generated IR
  and generic-body counts; distinguish dispatch costs from short-run variance.

## Execution

- Track external compile-time reads in build dependencies/cache identity.
- Separate host execution from target semantics for cross-compilation.
- Reduce remaining execution metadata retention and collection traversal cost
  when long sessions justify it. Immutable payloads are reclaimed between
  successful invocations; public snapshots, frame identities, literal backing
  and acquisition metadata retain their existing lifetimes. Use `aggregates`
  and `float_parsing` as controls; report payload backing separately from the
  metadata arena. Baselines and reproduction commands belong in the
  [performance notes](../docs/compiler-performance.md).

Validate with growing sessions, allocation failures, rollback and native/VM
comparisons. Safety extensions need aliasing and duplicate-cleanup rejections.

References: [resolution boundaries](../docs/semantic-resolution.md),
[Safety](../description/34_safety_model.md#precision-of-safety-effects),
[virtual contracts](../description/134_virtual_types.md).
