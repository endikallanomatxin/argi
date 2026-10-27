# Nominal types and parameterized definitions

This is the design reference for `refactor/nominal-type-values`, not a description
of functionality already implemented. Prefer removing old mechanisms to retaining
parallel systems. Keep the existing incremental graph, transactions, Safety, and
execution pipeline.

## Objective and scope

Complete the nominal type/value model across the compiler, core, more, tooling,
documentation and tests. Preserve definition identity and transparent aliases,
contextual construction, ordinary signature types, generic contract operations
and associated argument families. Consolidate semantic storage and remove
superseded mechanisms while retaining incremental transactions, Safety and
consistent native, bytecode, REPL and compile-time execution.

Keep the existing `#(...)` syntax for compile-time parameters and specialization.
Changing those delimiters is not part of this refactor. The syntactic spelling
must not alter the model of parameterized definitions as compile-time values.
Work in coherent implementation and validation batches. Keep the local compiler
architecture audit and `for-later.md` uncommitted.

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
Box := #(.T: Type) (.value: T)
identity := #(.T: Type) (.value: T) -> (.result: T) {
    result = value
}
OtherBox := Box
```

`#(...)` introduces compile-time parameters on a definition expression; after a
family value it supplies specialization arguments, not ordinary call arguments.
`Box` is a family; `Box#(Int32)` is a concrete type. `OtherBox#(Int32)` selects the
same specialization. Two independently written definitions remain distinct.
Named arguments use the same delimiters, for example
`base | convert#(.to: UIntNative)(_)`. Runtime arguments retain `(...)`.
`#run` and `#if` retain their directive spelling.
Conformance parameters use `implement#(.T: Type) Protocol#(T) (...)`. The same
compile-time delimiters apply to contract participants and dependencies. Empty type
literals may retain an explicit annotation, for example `Marker: Type = ()`.

`#(...)` explicitly delimits compile-time parameters and specialization arguments.
Ordinary parentheses delimit runtime arguments and record definitions. The parser
recognizes the hash marker directly; comparisons retain their ordinary grammar,
without specialization lookahead, speculative parses, or splitting `>=` tokens.
Nested specializations use ordinary balanced parentheses, for example
`Box#(Box#(Int32))`. `#run` and `#if` remain distinct directives.

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

The `once` modifier also belongs to the function definition value:
`acquire := once Args -> Result { ... }`, or `generic := once #(...) ...`.
Aliases preserve its function identity and consumption restriction. Declaration-
prefix once syntax and its dedicated declaration node are removed. Concrete functions also have
stable definition identities, so ordinary and once aliases retain the original
FunctionId rather than creating wrappers or fresh single-use state.

## Contextual construction and function signatures

Value literals construct values of an expected concrete type; they do not define
new types or convert between independent nominal types.
Generic specialization must preserve this rule instead of synthesizing a
structural type from the fields of an uncontextualized value literal.

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
a signature/type family, not several conflicting `Init#(String)` conformances
distinguished by a free allocator parameter. Do not impose a provider participant
on every protocol or implicitly erase allocators to virtual values.

A written constructor target fixes the `T` participant of `Init#(T)`; identical
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
`.copy: #(.Value: Type) (.value: Value) -> (.result: Value)`. Their lexical IDs are
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
generic declaration syntax and structural fallbacks once callers
are migrated. Update core, more, formatter, editor support, descriptions, and diagnostics with each migration.

Validate coherent batches rather than each mechanical edit. Cover alias identity,
independent same-shape definitions, repeated/nested specialization, missing context,
defaults, generic capabilities, rejected transactions, cached modules, REPL, and
`#run`; compare native and bytecode behavior where execution is involved.

Open details: generic operation/family signature syntax and checking; precise
multiple-output construction/destructuring; classification of compile-time family
parameters; and phase-safe introspection. Settle these at the relevant boundary
before adding implementation exceptions.

## Current state and remaining work

The branch uses `#(...)` throughout. Definition expressions own generic
parameters; type/function families and aliases retain stable originating IDs and
captures. Struct and payload-choice identity is separate from representation.
ModuleSema uses shared canonical pools instead of discovery/body overlays and a
final canonicalization copy. Definition completion remains transactional.

Named, imported and deferred function signatures retain their input/output type
identities, defaults and dependencies. Contextual construction, generic aliases,
associated families and compile-time entries use the common resolution pipeline.
Existing focused coverage includes native, VM, REPL and `#run`; that coverage is
not proof that the complete migration passes.

Implementation-owned operation signatures use `.operation: _`. Their definitions
or aliases use ordinary function inference, defaults, reached capabilities and
Safety. Qualified static calls work; erased virtual interfaces require fixed
signatures. General unqualified inference and projected signature properties
remain to be completed where required by the final contract design.

Init now has only T as participant. The constructor resolver selects its evidence
before inferring operation-local parameters and passes ordinary inputs directly.
There is no two-participant Init or wrapping of construction inputs in Args.
Arithmetic now also selects by two operand participants and calls an
implementation-owned signature directly. Auxiliary providers specialize the
callable. The legacy argument-record inference and wrapping path has been
removed; named records remain ordinary signature types, including MatrixProductArgs.
Partial-target inference maps the operation's captured parameter IDs back to the
implementation by capture position. Different inferred targets are ambiguous;
conformance specificity only compares candidates for one concrete tuple.

Core, more and 104 former fixture implementations have been migrated. Auxiliary
providers belong to the init function unless they are part of the target type.
Named once acquisition functions retain their identity and named input types.
Utf8Decoder takes byte views; text explicitly projects its bytes. File retains
its once empty-handle Init, uses file_from_stream for native stream handles, and
FileOpening/AllocatingFileOpening for fallible path factories.

Input defaults remain signature recipes until a caller omits an argument.
Contextual aggregate completion captures lexical assumptions alongside visible
bindings, preserving caller-owned temporary storage and capability inference.
Literal defaults retain the destination width for ordinary range validation.

Outstanding before completion:

- Finish and validate generic selected-evidence queries: a generic operation can
  have many concrete functions, and matching its family alone is insufficient.
  Captured argument values must match the selected conformance.
- Review remaining anonymous aggregate/choice identities, contextual literals,
  associated signature properties and generic operation inference against the
  design above. Remove obsolete representations rather than keep fallbacks.
- Complete unqualified lookup of implementation-owned signatures through shared
  input inference. Candidate probes roll back: any inferred participant created
  by a probe needs a stable representation before it can survive that rollback.
  Do not retain provisional type IDs or infer from operation results.
- Check shorthand assume on named signatures whose fields become known late;
  current acquisition functions retain explicit assume bindings.
- Finish fixture diagnostics, editor navigation and declaration metadata cleanup;
  synchronize examples and documentation with the final APIs.
- Run complete internal/program suites, official formatting and differential
  native/VM/REPL/comptime coverage, including ownership, defaults, rejected
  transactions, imports, caches and generic cleanup.

The full internal suite passes after the function identity changes. Focused
program coverage passes for definition-value once syntax, alias reuse rejection,
generic and inline Init once consumption, C callback rejection and concrete
C-ABI definition values. Function aliases execute in native, VM and compile-time
contexts. Parameterized functions preserve the once property when materialized.
The focused equality program suite passes, including missing-capability and
duplicate-conformance diagnostics. The word-count use case also passes after
restoring standard hash-policy resolution through borrowed Equal evidence.
The complete contract program suite passes after the arithmetic migration,
including static provider inference in native, VM and #run execution. Required
operation results are checked against Result; auxiliary inputs cannot create
another conformance for one operand tuple. Former structural argument fixtures
now use explicit nominal argument families. The general run's shared phase passed
762 cases with 11 optional skips. Its reported worker failures now pass together
in a focused batch, including diagnostic locations, nominal signature reuse,
StringView concatenation and reason-set comparisons. Payloadless choice equality
selects ordinary Equal evidence through a private representation fact; distinct
nominal choices remain incompatible. A fresh complete run is still required;
no full program-suite success is claimed.
