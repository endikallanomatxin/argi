# Contract implementation

Contracts select evidence for a participant tuple. Associated elements belong to
that selected evidence, while operations remain ordinary dispatch families.
The unary compatibility resolver still keys evidence by one concrete type and
a contract declaration. Its generic arguments are associated outputs, not independent
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

## Associated type projection implementation

`Product#(A, B).Result` parses as a type projection. Parameterized IR preserves
generic projections until instantiation. Global semantizing prepares canonical
tuple evidence before materializing generic records or proving operation
signatures. It preserves nominal identity, rejects missing tuples and value
members in type positions, detects unresolved cycles, and rechecks tuple
uniqueness after resolving participant projections. The frontend cache stores
both forms with an updated wire version.
This affects syntax and semantics; codegen receives an ordinary resolved type.

## Associated integer projections

Retain `Contract#(A, B).Count` as a compile-time integer expression in
parameterized IR. Concrete type applications with dependent arguments use
anonymous parameterized type records, resolved after tuple associations are
prepared. Reuse canonical tuple selection and associated member kind checks.
Preserve symbolic expressions until participant bindings are available, without
inferring participants from projected integers. Cover array dimensions, generic
records, arithmetic, invalid members and frontend cache round trips. Syntax and
semantics change; codegen receives concrete integer dimensions and ordinary types.

## Remaining work

- Move unary participant binding into the conformance adapter and unify its
  selection/evidence with canonical participant tuples. Keep legacy source
  spelling and unary virtual ABI as compatibility surfaces while removing
  separate semantic selection paths.
- Enforce unary body-declared composition. Included contract identities are now
  retained, but their requirements are not inherited yet. Preserve legacy
  explicit contract-to-contract relations while implementing those proofs.
- Extend integer projections to ordinary runtime expressions and associated-value
  assignments in conformance declarations.
- Add tuple constraints to generic compile-time parameter checking, so declarations
  can use contract guarantees before concrete instantiation.
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

Integer projection validation: all 84 contract fixtures pass, including 19 new
cases. The full Debug regression passes 1,695 program tests and 361 internal
tests, with 11 and 1 skips respectively. Clean and persisted-cache LLVM for the
generic call argument fixture are identical; the warm frontend reuses all 27
modules. Generated IR uses concrete `[2 x i32]` storage and direct specialized
calls. The persisted snapshot test also verifies a negative-dimension edit.

## Concrete call projection arguments

Store dependent call arguments in syntax-free parameterized IR on the call's
external reference. Evaluate them through the shared generic evaluator after
conformance preparation, and pass canonical concrete arguments to existing
function and constructor selection. Cover named arguments, arithmetic, missing
members, imports, selection diagnostics and persisted snapshots. Syntax remains
unchanged; module/global semantics and the cache wire format change, while
codegen continues to receive ordinary specialized calls.

Concrete call projection validation: all 96 contract fixtures pass within a
197-case regression covering contracts, generics, compile-time parameters,
constructors and modules. The complete internal suite passes 361 tests with
one skip; the updated persisted snapshot test also passes after the final
argument-diagnostic changes. Clean and warm-cache LLVM for an imported concrete
call are identical, with all 28 modules reused and no runtime lookup. Twelve
new fixtures cover this extension, and the former unsupported-constructor case
is now a positive executable fixture.

## Unary participant normalization

Normalize each compatibility unary declaration to one synthetic Type participant
in the same ComptimeParameter table as explicit participants. Lower Self to an
ordinary parameter reference and remove the special abstract-self IR type.
Retain an explicit compatibility marker for source argument binding and existing
virtual receiver/domain protocols. Safety receiver identification must inspect
the participant parameter identity in the original requirement, never infer it
from matching concrete argument types. Migrate remaining bundled virtual labels
to contract, preserve legacy consumer aliases, and verify generics, static/virtual
safety, frontend persistence and emitted LLVM. This changes module/global
semantics and the cache schema; syntax and runtime representation stay stable.

Unary normalization validation: all 99 contract fixtures pass. The complete
regression passes 1,710 program tests and 363 internal tests, with 11 and 1 skips
respectively. Source-IR and persisted-cache tests verify the shared participant
identity, including legacy declarations and rejection of a wrong receiver's
borrowed result. Clean and warm-cache LLVM are identical, with all 27 modules
reused; static calls remain specialized and virtual handles retain two pointers.
Conformance selection and virtual evidence still use compatibility adapters;
their unification is the next migration step.
