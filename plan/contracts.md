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

## Remaining work

- Introduce declaration metadata distinguishing participant parameters from
  associated elements, using the existing `#(...)` compile-time syntax.
- Add participant-tuple conformance identities to ModuleSG and GlobalSG,
  including relocation, speculative rollback and persistent codec versioning.
- Preserve symbolic associated projections until the tuple is concrete.
- Select applicable conformances using structural pattern specificity; diagnose
  incomparable maximal candidates. Do not infer participants from associated
  results or attempt arbitrary constraint implication.
- Resolve operation families with ordinary dispatch before validating their
  selected signatures and safety effects. Never filter incompatible return
  types to fall back to another implementation.
- Define visibility and extension rules so imports cannot silently change the
  associated meaning of a previously checked projection.
- Replace receiver-only safety mappings with indexed participant mappings.
  Preserve dependencies between participants and independent storage domains.
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
