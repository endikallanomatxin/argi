# Contract implementation

Contracts select evidence for a participant tuple. Associated elements belong to
that selected evidence, while operations remain ordinary dispatch families.
The current abstract resolver instead keys evidence by one concrete type and an
abstract declaration. Its generic arguments are associated outputs, not independent
participants. Do not reinterpret those arguments as participants.

## Migration boundary

Syntaxing accepts `Name: contract = (...)` and `Type satisfies Name` through the
existing unary declaration and relation nodes. This preserves module identity,
associated compile-time arguments, static proofs, and virtual safety checking.
Tokenizing needs no keyword changes: these words are contextual identifiers.
Virtual handles and conversions accept `.contract` alongside the legacy
`.abstract` label. Positional virtual arguments use the canonical contract name.
No codegen or persistent semantic layout changes are needed for these spellings.
Core and more use the unary contract/conformance spellings. Keep legacy
declarations available for compatibility fixtures and external consumers.

## Concrete participant tuples

Keep associated parameters on the declaration name and declare independent
participants on the `contract#(...)` marker. Lower both groups into distinct
ComptimeParameter ranges so their identities cannot be interchanged.
Standalone `satisfies Contract#(participants) = (associated arguments)` records
one joint conformance without selecting a privileged concrete receiver.

Syntaxing adds a conformance node and participant metadata. Module semantizing
persists named arguments and verifies every reference/range; the cache codec
needs a wire-version bump. Global semantizing binds and normalizes the complete
tuple, rejects duplicate concrete conformances, validates operations and their
safety promises, and records rollback-safe evidence independently of runtime
virtual registries. Operation IDs make conformance bodies semantic roots even
when main never calls those operations. Codegen remains ordinary function dispatch.

Initially accept concrete conformance declarations. Reject generic conformance
binders, unary use of explicit participant contracts, Self requirements,
composition and erased participant evidence until their semantics are modeled.

## Remaining work

- Enforce unary body-declared composition. Included contract identities are now
  retained, but their requirements are not inherited yet. Preserve legacy
  explicit contract-to-contract relations while implementing those proofs.
- Preserve symbolic associated projections until the tuple is concrete.
- Select applicable conformances using structural pattern specificity; diagnose
  incomparable maximal candidates. Do not infer participants from associated
  results or attempt arbitrary constraint implication.
- Extend tuple operation resolution to generic implementations and ordinary
  specificity ranking. Preserve input-first resolution and validate associated
  outputs after selection. Keep proof bodies active without forcing runtime
  reachability or allocating runtime evidence.
- Define visibility and extension rules so imports cannot silently change the
  associated meaning of a previously checked projection.
- Extend indexed input safety proofs to participant storage domains and joint
  opaque-state effects. Concrete tuple requirements already preserve ordinary
  multi-input dependencies without synthesizing a Self receiver.
- Extend virtual evidence to jointly packaged participants. Keep selected
  operations fixed at construction and require explicitly representable results.
- Replace unary Self-bound library declarations once participant and associated
  syntax is settled; remove legacy names only after compatibility fixtures and
  external migration guidance are ready.

## Validation

Cover ordinary and constrained static calls, generic conformances, associated
compile-time types and values, composition with legacy abstracts, imported
identities, virtual dispatch, missing operations and borrowed-result escapes.
Check clean and reused frontend builds and emitted LLVM dispatch representation.
