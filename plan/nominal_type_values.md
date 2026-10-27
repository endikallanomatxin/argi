# Nominal types and parameterized definitions

This is the design reference for `refactor/nominal-type-values`, not a description
of functionality already implemented. Prefer removing old mechanisms to retaining
parallel systems. Keep the existing incremental graph, transactions, Safety, and
execution pipeline.

## Values, definitions, and identity

Declarations bind names to compile-time or runtime values. They do not create
nominal identities. Struct and choice type-definition literals create nominal
types, including unnamed definitions. Independent definitions are distinct even
when their fields, variants, defaults, and layouts match.

```argi
Point := (.x: Float64, .y: Float64 = 0)
OtherPoint := (.x: Float64, .y: Float64 = 0)
Alias := Point
```

`Alias` and `Point` are the same type; `OtherPoint` is different. References,
arrays, and error reason sets may retain identities derived from their components.
Use a one-field nominal struct for a distinct index or other scalar wrapper; no
additional nominalization syntax is required initially.

Identity and representation are separate. Contracts provide behavior; matching
representation grants neither conformance nor implicit conversion. Preserve all
storage, lifetime, movement, and cleanup obligations across wrappers and aliases.

## Parameterized definitions are compile-time values

The parameter list belongs to the definition expression:

```argi
Box := <.T: Type> (.value: T)
identity := <.T: Type> (.value: T) -> (.result: T) {
    result = value
}
OtherBox := Box
```

`<...>` introduces compile-time parameters on a definition expression; after a
family value it supplies specialization arguments, not ordinary call arguments.
`Box` is a family; `Box<Int32>` is a concrete type. `OtherBox<Int32>` selects the
same specialization. Two independently written definitions remain distinct.
Named arguments use the same delimiters, for example
`base | convert<.to: UIntNative>(_)`. Runtime arguments retain `(...)`.
`#run` and `#if` retain their directive spelling.
Conformance parameters use `implement<.T: Type> Protocol<T> (...)`. The same
angle delimiters apply to contract participants and dependencies. Empty type
literals may retain an explicit annotation, for example `Marker: Type = ()`.

Tokenization emits ordinary `<` and `>` tokens. Syntaxing alone determines whether
they form specialization syntax or comparisons, using context and syntactic
lookahead, without type lookup or significant whitespace. Where both parses are
possible, specialization takes priority; explicit scalar grouping with `[...]`
expresses the comparison interpretation. Define valid continuation tokens and
lookahead boundaries before implementing that rule. Cover nested specializations
such as `Box<Box<Int32>>`, specialized values without a following call, ordinary
comparisons, and diagnostics for missing closing delimiters. Semantic analysis
receives a single interpretation and does not retry the other parse on failure.
Positional specialization arguments are comma-separated. Comparisons and logical
expressions used as specialization arguments require scalar grouping with `[...]`,
so ordinary conditions containing `<` and `>=` remain comparisons.

Definition identity comes from the definition site and its enclosing compile-time
specialization environment. Specialization adds its explicit/inferred parameters.
Re-evaluation and delayed materialization must not generate fresh identities.
Returning or binding an existing type/family preserves its identity. A generic
alias that returns `T` does not create a wrapper around `T`.

Families may be bound, passed, and returned in compile-time contexts while keeping
their precise classification and identity. They have no runtime representation.
Captured dependencies must be compile-time values; identity must include captured
specialization bindings that affect meaning. Runtime storage cannot be captured.
A family value carries its originating definition and a range of captured lexical
arguments. Its compile-time classification identifies the producer; the captures
belong to the value. Specialization binds that prefix before interpreting the
caller's own arguments, which cannot overwrite captured bindings. Use existing
canonical argument pools rather than copying templates or allocating a new nominal
definition for each captured environment.
Aliases retain the original definition's lexical context and ownership. Distinguish
definition visibility from legitimate instantiation context; materialization timing
must not change resolution.

Initially support parameterized type, function, and contract definitions. Do not
treat the prefix as arbitrary compile-time execution or introduce runtime closures.

## Contextual construction and function signatures

Value literals construct values of an expected concrete type; they do not define
new types or convert between independent nominal types.

```argi
point: Point = (.x = 10)
other := Point(.x = 10)
```

An aggregate value literal without sufficient type context is rejected. Defaults
belong to the type definition and are completed during contextual construction.

Function input and output records are ordinary types. Named types can be used
directly as signatures, alongside inline definitions. Do not add a `Parameters`
metatype or a structural-compatibility exception for function signatures.
Implementations must reuse their required signature identities; contextual
implementation bodies can obtain the expected signature without independently
redeclaring equivalent nominal types.

## Contracts and generic operations

Contract participants identify a conformance. Its associated elements are unique
for that participant combination. An operation may itself have compile-time
parameters, including constrained allocator types, independently of conformance
selection. Its argument type can depend on those operation parameters.

Operation identity is resolved first. Candidate signatures can help infer unknown
participants; unresolved ambiguity requires explicit disambiguation. This does not
introduce ordinary-function overloading or let associated values distinguish two
conformances for the same participants.

The intended direction is to remove argument records as incidental conformance
participants in protocols such as `Init` and arithmetic. A concrete `.Args: Type`
is sufficient only for a non-generic argument type. A generic operation requires
a signature/type family, not several conflicting `Init<String>` conformances
distinguished by a free allocator parameter. Do not impose a provider participant
on every protocol or implicitly erase allocators to virtual values.

A written constructor target fixes the `T` participant of `Init<T>`; identical
argument shapes on other targets introduce no ambiguity. Arithmetic operands fix
`Left` and `Right` in the same way. Auxiliary arguments and allocator types belong
to the operation signature and associated `Args`, not additional conformance
participants. Infer remaining operation parameters from inputs and require explicit
arguments when that inference is ambiguous. A partially specified target can still
require input inference, but must preserve every explicitly supplied parameter.

Operation implementation compatibility is separate from type equality. Required
inputs match by position, name and ordinary type equality; additional implementation
inputs need defaults. Outputs match exactly in count, names and field types. This
rule does not equate the enclosing nominal signature records or permit conversions
between independently defined field types. Generic aliases infer their parameters
from the required inputs, including through named signature families, never outputs.

Operation parameters belong to the signature expression, for example
`.copy: <.Value: Type> (.value: Value) -> (.result: Value)`. Their lexical IDs are
separate from participant and associated-element IDs. Each operation owns its
parameter scope; sibling operations may reuse names, while shadowing contract
parameters is rejected. These parameters specialize an already selected operation,
not the conformance. Publishing a conformance must retain the operation definition,
rather than require one prematurely instantiated body for all specializations.

Generic operation signatures and bodies are checked for selected static
instantiations, as ordinary generic functions are. A conformance retains the
selected definition; it does not fabricate a representative body or introduce a
second specialization cache. Concrete calls must satisfy the instantiated
requirement before publication. Virtual use requires a fixed supported interface
and must not bypass these checks.

Before migrating those protocols, specify how contracts declare generic operation
signatures, how associated families share their parameters, and how implementation
compatibility is verified. Preserve static inference, explicit/reached capability
rules, safety summaries, and virtual signature restrictions.

## Implementation sequence and acceptance

1. Make definition expressions and their parameter scopes explicit in syntax and
   semantic templates; declarations reference their values. Preserve stable IDs.
2. Separate definition/type identity from representation; make aliases transparent
   and use definition plus specialization identity for nominal types.
3. Implement contextual aggregates and ordinary named signature types, including
   defaults, multiple outputs, and implementation signature identity.
4. Complete the generic-operation contract design and migrate `Init`/operators.
5. Consolidate ModuleSema fields, variants, types, and remaining overlays around
   this model. Avoid new copies, translation layers, or persistent scratch state.

The existing canonical generic-argument pool is a compatible first simplification.
During migration, keep intermediate states explicit and remove declaration-bound
generic syntax, `#(...)` specialization, and structural fallbacks once callers
are migrated. Update core, more, formatter, editor support, descriptions, and diagnostics with each migration.

Validate coherent batches rather than each mechanical edit. Cover alias identity,
independent same-shape definitions, repeated/nested specialization, missing context,
defaults, generic capabilities, rejected transactions, cached modules, REPL, and
`#run`; compare native and bytecode behavior where execution is involved.

Open details: generic operation/family signature syntax and checking; precise
multiple-output construction/destructuring; classification of compile-time family
parameters; and phase-safe introspection. Settle these at the relevant boundary
before adding implementation exceptions.

## Progress

- Discovery and later lowering share canonical type, field, variant, and
  generic-argument pools. One interface constructor handles local/imported types;
  the early duplicate builder, prefix offsets, field/variant overlays, and final
  canonicalization copy are removed. Functions also use one canonical record;
  the interface/body metadata overlay and its linear lookups are removed.
  Declaration metadata still needs consolidation.
- Syntax stores function definitions and parameterized definitions independently
  of their binding names. Calls reference callee expressions; type and function
  applications share specialization nodes. Parameter and specialization lists
  are distinct from struct type literals.
- Angle syntax, syntactic disambiguation, named signature syntax, and formatter
  spacing are implemented. An integration fixture executes definition expressions
  through native code, VM, and `#run`.
- Concrete type values can be aliased across bindings and modules, used in
  signatures and construction, and evaluated through `#run`. Deferred type uses
  participate in the ordinary pending-work mechanism.
- Unspecialized type/function families have a distinct compile-time value
  classification, without runtime storage. Binding and module aliases preserve
  their original templates and specialize through ordinary resolution. Concrete
  types and families share alias traversal but remain distinct classifications.
- Concrete nominal types reference independent type-definition IDs. Definitions
  own layouts, fields, variants and callback prototypes; declarations bind their
  type values. Source-name associations are optional and do not determine equality
  or module ownership.
- Generic types, function specializations, contracts, operations, and selected
  evidence use independent family-definition IDs. Definitions locate their
  templates directly; declaration associations provide names and navigation.
  Anonymous type definitions still need migration. Legacy spellings still parse
  into the common definition representation during migration.

### Current aggregate migration boundary

- Concrete and parameterized records and closed choices with payloads retain
  their source definition identity.
  Dependent instances include captured compile-time arguments; repeated lowering
  reuses identities. Diagnostic source remapping does not affect identity.
- Definition completion is journaled. Speculative type recipes preserve origin,
  arguments, representation and defaults, including completion of retained IDs.
  Compile-time entries capture demanded ambient bindings; own parameter defaults
  do not acquire unused self-dependencies through signature record identities.
- Concrete and specialized function interfaces retain input/output Type IDs.
  Local named records supply signatures and defaults; explicitly specialized
  functions also bind fields from named generic signature types. Input inference
  follows those definitions and maps their parameter bindings back to the caller,
  including ordinary reached defaults. Inline implementations are
  constructed against their selected required signature. Ordinary operation
  aliases infer parameters from corresponding inputs and retain their own types.
- Named once capability constructors share explicit Args definitions with Init.
  A native/VM fixture covers named signatures, defaults and calls through #run.

- Imported and deferred record signatures complete through ordinary pending work,
  retaining their concrete function identity. Their bodies bind the completed
  fields and defaults; qualified and closed specialized signatures share this
  path. Non-record signatures receive semantic diagnostics. Integration coverage
  exercises native execution, VM and `#run`.

- Input inference traverses composed signature families and carries inferred
  bindings back through each lexical parameter list. Explicit type declarations
  accept parameterized definition expressions as their value.

- Parameterized aliases complete their provisional application with the returned
  semantic type rather than acquiring a family-based nominal identity. Input
  inference follows their definition body using the same lexical binding transfer
  as composed signatures; pointer prefilters do not reject transparent aliases by
  their family name. Native/VM coverage includes round-trip assignments, alias
  parameters and an identity type family.

- Type-valued declarations, including parameterized aliases, use ordinary
  constant binding syntax regardless of whether `: Type` is written. Family
  classification comes from the definition expression; aliases whose bodies are
  type parameters, references, arrays or other specializations need no annotation.
  The separate ordinary type-declaration AST node is removed; C representation
  declarations retain their explicit foreign forms.
- Closed `Name: Type = value` declarations use ordinary constant bindings, just
  like inferred type-valued declarations. Explicit annotations do not nominalize
  an existing type. The nominal `underlying_type` representation and its separate
  lowering, validation and backend paths are removed; scalar wrappers require a
  record definition.

- Nominal assignment checks cover whole values and typed aggregate children,
  rather than only scalar wrappers. The old wrapper fixtures now distinguish
  transparent annotated aliases from independent one-field record definitions.
  Cyclic closed aliases are diagnosed after pending resolution stalls. Context
  cannot retag an already constructed nominal value; this is checked before
  record completion as well as during ordinary literal coercion.

- Contract requirement syntax and ModuleSema retain operation-local compile-time
  parameter ranges independently of participants and associated elements. Their
  bounds and signature types are lowered in a scoped environment, and the module
  verifier checks those ranges. Scoped static calls infer local parameters from
  inputs/reached defaults, check bounds, and instantiate the selected definition
  through the ordinary generic-function engine. Required outputs never infer them.

- Selected operation bindings retain their optional materialized function
  directly. The parallel per-conformance function-reference list is removed.
  Completion is monotonic and journaled, including nested transactions and
  allocation-failure rollback; reachability and verification use the same evidence.
  Generic bindings retain their definition instead of one materialized function;
  the verifier checks each called instance's selected definition origin.

- Inline operation definitions preserve their own parameter lists after captured
  conformance/associated bindings. The captured prefix is explicit in syntax and
  ModuleSema; local parameters retain normal bounds/default lowering and cannot
  shadow captures. Selected instances check callable input/output compatibility
  and ordinary Safety before execution, including implementations that alias
  ordinary generic functions. Safety proof selection keys both operation identity
  and specialized function; proofs from another instance are not reused.
  Native/VM/`#run` coverage combines ordinary and generic operations, differing
  parameter names, captured conformance bindings and incompatible output rejection.
- Unqualified candidates check operation parameter bounds/defaults before choosing
  an operation identity. Distinct applicable identities remain ambiguous. Generic
  operations are rejected explicitly at the virtual boundary. Interactive coverage
  retains accepted instances across rejected submissions; declaration Safety
  metadata is freed recursively, including partially built outcomes on allocation
  failure.

- Definition values retain origin plus captured argument ranges through aliases,
  relocation and specialized IR. Type/function application binds the lexical prefix
  before explicit arguments; bound-argument publication is shared. Internal tests
  cover distinct environments, pool growth and rejection of capture rebinding.
  Signature/body inference binds the same captured prefix, propagates only local
  arguments back to the caller and checks nominal application captures before
  inferring remaining parameters.
  Source construction of associated family values and their signature checking
  remain pending; the representation does not by itself complete that feature.

- Qualified static operations accept their own explicit specialization arguments,
  separately from contract participant arguments. Positional/named arguments bind
  before input inference; concrete and staged bodies use the same selected-evidence
  path. Parser and native/VM/`#run` tests cover both argument groups and reject
  unknown/excess operation parameters with semantic diagnostics.

- Multiple-output calls retain the signature's nominal output type rather than
  reconstructing a structural record from its field range. Static and virtual
  result typing share that rule; named-output assignments are covered in concrete
  and generic functions across native, VM and `#run`. Single-output unpacking
  remains an explicit outstanding part of the result-model consolidation.

- Safety selector lowering and ModuleSema verification consult read-only semantic
  signature field views, including closed named records, rather than assuming
  syntax literals. Views retain concrete/parameterized field namespaces without
  copying representations. Joint-output virtual Safety fixtures now share a named
  result type and retain their original correlated-borrow diagnostics. Locally
  available signature families expose their declared fields without instantiation,
  including symbolic participants. Imported/deferred fields still need late selector
  resolution.

- Static contract calls accept closed named input/output records and infer
  participants through named signature families using the existing function
  inference path. Receiver indices for Safety come from the selected concrete
  function signature. Native/VM/`#run` coverage preserves returned loans, and a
  negative case rejects escape after the source lifetime ends. Named signature
  families with declared Safety also work through virtual handles in native, VM
  and `#run`, using the existing interface and evidence selection.

- Repeated generic-binding conflicts discard only the losing operation candidate;
  they do not abort selection of another contract identity. Qualified calls retain
  their explicit conflict diagnostic. Native/VM/`#run` regressions cover losing
  patterns alongside bound filtering and genuine identity ambiguities. Universal
  compatibility of generic definitions remains separate from per-instance checks.

- Nominal specialization lookup shares the existing generic identity index,
  distinguishing nominal-definition and family origins in its keys. Validated
  hits avoid the definition-pool scan; semantic equality remains the fallback for
  recursively equivalent arguments and spelling differences. Existing cache
  checkpoints cover rollback, with tests for repeated hits, ID reuse and wrong
  entries. This reduces repeated lookup work without another persistent cache.

- Formatting treats syntax-confirmed angle lists as logical delimiter groups,
  sharing the 96-column reflow policy with ordinary arguments. Comparison tokens
  retain their original lexical text; token/syntax preservation and repository
  idempotence checks remain active. Combined `>=` closers keep their original
  layout until their assignment token can be represented independently.

- Compile-time argument pools now distinguish definition values from concrete
  types and integers. Inference, relocation, equality and argument publication
  preserve their origins and captures. Deferred defaults and speculative type
  recipes retain the same environment through rollback; allocation-failure tests
  cover reconstruction. Type-family parameter signatures use `<.Item: Type> Type`
  in annotations and associated declarations. Their nested binders have separate
  scopes and do not add arguments to the enclosing definition. Module verification
  checks their ranges and parameter kinds. Associated family construction,
  application and implementation-signature compatibility remain open.

- Type-family parameters can be passed explicitly, forwarded and specialized in
  function signatures/bodies; family defaults use the same captured values.
  Retained definition references distinguish lexical family parameters from named
  declarations. Explicit binding checks remaining arity and parameter kinds;
  Bound compatibility rejects extra restrictions on an unrestricted signature
  and compares explicit contract identities and symbolic arguments under
  alpha-renaming. Unrestricted supplied families remain usable where a bound
  is promised. General implication through contract composition remains pending.
  Concrete call arguments now share the retained-IR lowering path, removing the
  separate literal-only evaluator. Scoped operation and virtual-evidence consumers
  resolve those arguments through the common resolver. Native, VM and `#run`
  fixtures cover application, forwarding, defaults and arity rejection.

- Associated family implementations can provide a named parameterized type value
  with a family signature annotation. Operations specialize that selected family
  through their own parameters; captured associated-family signatures retain their
  metadata without becoming operation defaults. Native/VM/`#run` cases exercise
  multiple operation instances, and invalid family arity produces a conformance
  diagnostic. Associated projections as family arguments and universal bound
  compatibility are still outstanding.

- Associated family projections can be specialized directly in type annotations,
  including generic signatures and `#run`. Resolution selects ordinary conformance
  evidence and retains the provided family's nominal identity; it creates no new
  family or nominal wrapper. A definition-reference projection carries its source,
  contract base and member through retained IR. Tests distinguish concrete type
  members from family members and preserve identity against the named family.
  Unspecialized projections in compile-time argument position now retain a
  value-projection recipe until conformance selection determines whether the
  associated element is a type, integer or family. Ordinary specialization,
  signature inference and constraint matching consume the same selected value;
  they do not infer participants backwards from an associated result.
  Native/VM/`#run` fixtures cover all three kinds and generic forwarding; a REPL
  regression checks rejection rollback and continued use of accepted values.

- Inline associated type-family definitions share private declaration discovery,
  nominal type lowering and ordinary specialization with named definitions. Generic
  implementation parameters form the family's captured prefix; local family
  parameters remain its public specialization arguments. Internal verification
  checks retained lexical IDs, and native/VM/`#run` fixtures cover captures and
  projected layouts. Equal field representations from different captured
  conformances remain nominally distinct. No associated-family template registry
  or separate identity cache is introduced.

- Unqualified operation calls accept positional/named explicit operation arguments.
  Candidate probes bind them before input inference, bounds and conformance
  selection; distinct applicable identities remain ambiguous. Concrete, staged and
  interactive calls use the same selection path. Ordinary generic applicability
  reuses explicit selection without materializing bodies during probes. Native,
  VM, `#run` and REPL rollback tests cover explicit operation instances.

- Family signature shape checking descends recursively through family-valued
  parameters, with a bounded depth. Matching outer parameter kinds alone no longer
  accepts incompatible nested arities. Positive nested application and negative
  nested-signature fixtures complement the existing top-level arity checks.
  Integer parameter types are compared by semantic identity, including aliases,
  nested signatures and captured lexical environments. Explicit bounds compare
  symbolic parameter positions, reference types and fixed arguments rather than
  testing a representative instance. Contract-composition implication remains
  outside this check; this does not claim universal signature compatibility.

- Specialization in value position uses a shared entity-application recipe.
  Type producers yield Type values; function producers retain their origin and
  canonical captured arguments without executing or duplicating a template.
  Module, lexical and retained interactive aliases invoke ordinary specialization
  and argument completion. Parameterized bodies and compile-time entries share
  that application path. Rebinding captured arguments and mismatched runtime
  inputs are rejected. Rejection diagnostics borrow static messages rather than
  leaking formatted strings outside transaction ownership.

- MatrixProduct now selects only Left/Right; Args is an associated nominal record
  shared by the general algorithm, diagonal specialization and Multiply adapters.
  Native/VM matrix-shape coverage and weighted regression exercise the same result
  projection. Init and the standard arithmetic protocols still require migration.

Still pending:
uniform classification of payloadless choice definitions versus referenced option sets, general contextual aggregate
inference, remaining generic-call inference parity,
associated type-family signatures and associated Args migration. Remove
remaining field-range-only consumers and legacy generic representation paths.
Bundled core/more sources, generated entrypoints, REPL preludes, scaffolding,
primitive signature specifications and editor type displays use angle specialization
and definition values. Constructor and operation fixtures must share nominal Args
identities; editor parameter classification uses signature binding references as
well as field origins. Full internal validation reached 1,027 passes with one
skip and one editor failure; the subsequent focused checks pass after correcting
that failure. The test syntax migration is consolidated in one commit. Broad program validation
remains incomplete; the last full serial fixture group exposed constructor
inference and associated-projection failures, with other diagnosed failures
subsequently repaired. Init/arithmetic Args still need their associated-family migration;
syntax migration alone does not complete that semantic change.

Concrete constructor migration case: explicit StandardHashPolicy input makes both
HashMap Init implementations applicable. Their independently defined nominal Args
records prevent tuple coverage from establishing specialization. Reproduced with
`argi build tests/feature_tests/system/86_word_count_consumer --no-cache`.
Do not restore structural Args identity or rank unrelated nominal records by their
fields. Migrate to one Init conformance per target, with operation-level Provider
parameters and associated argument families. Standard-policy defaults belong to
the selected target's argument definition; custom policies remain explicit. Preserve
partial target inference and the existing noncopyable policy transfer behavior.
