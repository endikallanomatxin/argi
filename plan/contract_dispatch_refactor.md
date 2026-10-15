# Remaining contract dispatch work

The compiler uses unique ordinary functions, contract-scoped operation identities
and selected `implement` evidence. Core and more use Init, Convert, Deinit and
operator contracts. There are no legacy overload, constructor or destructor
registries or implicit participant/representation adapters.

## Remaining design work

- Define joint virtual evidence for several hidden participants, including its
  representation, ownership and lifetime relations.
- Extend symbolic dimension constraints conservatively without inverse inference.

## Independent diagnostic follow-up

Profile conformance verification independently from executable reachability.
Executable builds prove selected operation bodies and reached virtual evidence.
Exhaustive checks and editor diagnostics also prove unused concrete operations.
Setup profiling separates external types, conformance registration, associated
projections, materialization and signature validation. Registration separately
reports template checks and concrete tuples. Template comparisons are grouped by
contract identity and participant arity; closed builtin and concrete patterns do
not allocate module-wide substitution bindings. Mixed concrete/symbolic comparisons
reuse the conservative shape filter before materialization, rejecting incompatible
nominal identities without constructing irrelevant generic instances.

Generic constraint diagnostics allocate substitutions only for declarations with
applicable type constraints. Error inference rebuilds its candidate signatures
on each global pass and reuses scratch capacity across functions and rounds;
recursive convergence and signature changes remain observable. Executable builds
infer summaries for reached functions, including inferred-signature roots;
exhaustive checks and editor diagnostics retain all bodies. Propagation refresh
skips its node scan when neither propagation nor context records exist. Summary
inference and propagation refresh have separate profiling counters.

Instance ID translations use lazy pages rather than initializing module-sized
value maps for every function or signature probe. Pages remain instance-local,
including speculative work and deferred body reconstruction. Default string
literal lookup uses the complete declaration index with traversal fallback;
binding materialization visits compact unresolved-state metadata first.

Reprofile per-module substitution maps and full-pool materialization sweeps
before replacing them with function-local storage or unresolved-item worklists.
Preserve signature binding/default identities and speculative rollback when
changing their storage.

Before reusing validated core graphs or summaries, specify invalidation for
source, target, imports and specialization visibility. Preserve selected operation
identities and all conformance diagnostics.

Signature probes currently collapse some instantiation failures into pending
resolution. Distinguish definite errors from missing bindings without exposing
errors from losing candidates. Explicit and inferred calls now share argument
publication, but their initial inference rules remain distinct.

## Validation

Use focused contract, polymorphism and editor checks with parallel workers,
then the complete regression. Preserve selected-evidence rollback, associated
signature checking, virtual safety proofs and cold/warm frontend equivalence.

## Ordered comparison migration

Compare#(Left, Right) classifies two explicit operand values with an infallible
Ordering result: less, equal, greater or unordered. CompareRelations#(Left, Right)
requires Compare and the four Bool predicates. A normal generic implementation
supplies the predicates through ordinary core functions. More specific concrete
and generic implementations replace that implementation, including direct scalar
representation hooks. No optional operations, default operation bodies, Args
participant or inverse inference are involved.

TotalOrder is a semantic promise over Compare, available for integers, Bool and
Char but not floating-point types. All derived predicates return false for unordered.
C enum and callback equality uses Equal through checked empty representation facts.
Tag tests keep their control-flow representation. Codegen reuses native predicates.
