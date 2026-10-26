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
  canonicalization copy are removed. Function/declaration metadata still needs
  consolidation.
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
