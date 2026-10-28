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
| Generic/associated types | Bound parameters and conformances | Fields, defaults and nullable/Errable representations |
| Error inference | Available bodies and propagation paths | Reason sets and revised propagation result types |
| Reached inputs and conformance validation | Current signatures and lexical contexts | Updated calls and selected operation bodies |
| Compile-time request materialization | Stable recipes and available semantic dependencies | Executable bodies needing ordinary resolution and cleanup |

The inner fixed point repeats when these facts change. It is not restricted to
new pool tails: old unresolved slots can complete, and typed expressions may
receive a different contextual type. Execution reachability alone is insufficient
to select all type-propagation operands required by ownership finalization.

After quiescence, ownership finalizes eligible bodies. Cleanup can make more
functions reachable, so resolution resumes before finalizing those bodies.
Compile-time evaluation additionally waits for its bodies and dependencies to
be ready; the scheduler arranges readiness, while verified bytecode performs
execution. Completed results may unlock another resolution round.

`completeUnit()` then diagnoses unresolved/invalid work and checks unit integrity.
Checked compilation also performs Safety and once verification before execution
publication. Neither a published function signature nor an empty worklist replaces
these boundaries.

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
owns auxiliary references to those IDs, including caches, reached calls and
captures. Contract checkpoints own their conformance and virtual-signature
diagnostics. Session rollback also restores scheduler completions and persistent
interactive state.

A discarded candidate releases its new compile-time requests. A genuinely
suspended selection can explicitly retain request recipes while rolling back
provisional graph entities; an outer rejected transaction can still discard
those recipes. Do not retain requests for losing candidates merely because they
performed compile-time probing. Request recipes must not retain provisional IDs.

For measured costs and rejected optimization approaches, see
[compiler performance](compiler-performance.md). Remaining implementation work
belongs in [compiler follow-ups](../plan/compiler.md).
