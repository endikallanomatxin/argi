# Semantic resolution boundaries

The retained semantic session uses the same resolution and ownership passes as
ordinary compilation. `advanceResolution()` in
`src/4_semantics/global/semantizer.zig` reaches quiescence; quiescence alone is
not permission to publish or execute a unit.

## Dependencies

| Work | Requires | Can produce more work |
|---|---|---|
| Selected generic bodies | Published identities and signatures | Nodes, types, calls and evidence |
| Pending operations | Their operands, visible declarations and selected evidence | Specialized functions, contextual types and compile-time requests |
| Binding and expression types | Initializer/operand types | Types needed by calls, references and contextual construction |
| Contextual values | Expected types and aggregate shapes | Nested literal types, including in previously created nodes |
| Reference types | Operand types and existing reference permissions | Address and dereference types, including previously typed nodes |
| Generic/associated types | Bound parameters and conformances | Fields, defaults and nullable/Errable representations |
| Error inference | Available bodies and propagation paths | Reason sets and revised propagation result types |
| Conformance validation | Declared operation signatures and lexical assumptions | Selected operation bodies |
| Compile-time request materialization | Stable recipes and available semantic dependencies | Executable bodies needing ordinary resolution and cleanup |

The inner fixed point repeats when these facts change. It is not restricted to
new pool tails: old unresolved slots can complete, and typed expressions may
receive a different contextual type. Execution reachability alone is insufficient
to select all type-propagation operands required by ownership finalization.
Address and dereference materialization share one source-ordered graph scan.
They derive types from operands rather than certifying a node permanently;
later contextual changes still revisit both forms until the fixed point settles.
Writing the same unresolved IDs is not progress: semantic type equality rejects
unresolved types, so propagation compares the actual stored IDs and annotations
before reporting a change. Stable pending facts must allow quiescence and normal
unresolved diagnostics rather than forcing another identical resolution round.
Error-result refresh treats the payload projection and its result type as
separate facts. A transparent field can retain index zero while its type changes;
stable projection metadata alone does not certify the propagated expression type.

After quiescence, ownership finalizes eligible bodies. Cleanup can make more
functions reachable, so resolution resumes before finalizing those bodies.
Compile-time evaluation additionally waits for its bodies and dependencies to
be ready; the scheduler arranges readiness, while verified bytecode performs
execution. Completed results may unlock another resolution round.

`completeUnit()` then diagnoses unresolved/invalid work and checks unit integrity.
Checked compilation also performs Safety and once verification before execution
publication. Neither a published function signature nor an empty worklist replaces
these boundaries.

Executable field defaults use the same captured-expression recipes for concrete
and generic signatures. Each omitted field instantiates its recipe with the
field's expected type and the caller's lexical assumptions. Addressed temporaries
belong to that caller's scope; neither the expression's storage nor its effects
are shared between calls. Literal defaults remain inline.

## Ownership staging versus backend lowering

Ownership staging is semantic preparation shared by LLVM and bytecode. An early
exit while evaluating a later aggregate or call operand must clean earlier owned
operands. `stageCompound()` therefore introduces ordinary lexical bindings and a
value sequence, then moves staged operands into the completed aggregate or call.
The original expressions execute once and retain their evaluation order. Virtual
receivers and indirect callees must also retain single evaluation.

This transformation precedes recursive cleanup finalization. It uses selected
Deinit evidence and ordinary storage identities; it does not implement a second
runtime ownership model. Backend lowering consumes the resulting semantic plan,
including checked replacement plans, rather than rediscovering destruction rules.

## Transaction ownership

Graph rollback owns provisional IDs and reversible completions. Resolver undo
owns auxiliary references to those IDs, including caches and captured expressions. Contract checkpoints own conformance resolution state. Virtual-signature
diagnostics have a different lifetime: generic applicability probing may discover
an invalid conversion that must still explain why the enclosing call failed after
its graph is rolled back. These source-based explanations survive local probes;
the outer resolver checkpoint restores them when rejecting the whole submission.
Session rollback also restores scheduler completions and persistent interactive
state. Diagnostic retention is not permission to retain provisional graph IDs.

A discarded candidate releases its new compile-time requests. A genuinely
suspended selection can explicitly retain request recipes while rolling back
provisional graph entities; an outer rejected transaction can still discard
those recipes. Do not retain requests for losing candidates merely because they
performed compile-time probing. Request recipes must not retain provisional IDs.

For measured costs and rejected optimization approaches, see
[compiler performance](compiler-performance.md). Remaining implementation work
belongs in [compiler follow-ups](../plan/compiler.md).
