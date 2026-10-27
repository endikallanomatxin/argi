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

Canonical construction uses `Init#(Target, Args)`. Both parameters are concrete
nominal types identifying a conformance. `Result` is associated and must be Target
or one Errable containing Target. The required operation is
`.init: Args -> (.result: Result)`; construction has no open-signature exception.

`T(...)` fixes Target and infers Args against applicable input signatures, without
inventing structural identities for call literals. Generic implementation parameters,
including allocator types, must be determined by the participants. They specialize
the selected implementation through Args; no virtual allocator is required.

Several conformances may target the same type. Different inferred argument types
are ambiguous unless the call is explicitly disambiguated. Specificity compares
only conformances for the same complete tuple. Different target types may share
argument types or shapes. Return types never select a conformance. Partially
specified targets preserve every explicitly supplied parameter.

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

Fixed and declared-generic signatures use the compatibility rule above. An
implementation-owned operation does not provide a fixed virtual interface;
virtual use must reject it. Init uses its explicit Args participant rather than
an implementation-owned signature. Preserve static inference, explicit/reached
capabilities, safety summaries and virtual signature restrictions.

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

Multiple outputs form an ordinary named or inline result record. Reading named
fields and assigning the complete result use the same nominal rules as other
records. A new destructuring shorthand is not required for this refactor.
Compile-time families retain their producer classification and captures; they
are not runtime Type values or callable factories.

## Completed implementation and validation

Implemented:

- Definition expressions own compile-time parameters. Aliases preserve type,
  family, function and once identities, including lexical captures.
- Nominal record/choice identity is separate from representation. Named,
  imported and deferred signatures retain their types, defaults and dependencies.
- ModuleSema uses shared pools without discovery/body overlays or a final
  canonicalization copy. Definition completion remains transactional.
- Operation bindings retain ordinary expressions and captured prefixes. Associated
  members share the implementation scope; input inference never uses outputs.
- Core, more and constructor fixtures use Init#(Target, Args), with Result
  associated. Generic allocators specialize through Args. Standard hash collection
  construction supplies its policy internally; explicit-policy routes require it.
- Named inputs take lexical precedence over captured parameters. Deferred defaults
  reuse caller assumptions and roll back provisional effects before retrying.

Validation of 8506f809:

- Complete ReleaseSafe program suite: 2,444 passed, 11 optional skips, no failures.
- Complete Debug internal suite: 1,045 passed, one skip, no failures.
- Official formatter check passes for core and more; changed Zig files pass
  zig fmt and the worktree passes git diff --check.
- Init participant case 353 succeeds in native and VM execution, including its
  #run expression. Its LLVM contains direct calls to the selected implementations.

The implementation review found no remaining construction registry, unary Init
compatibility path, declaration-owned ordinary generic parameters or structural
identity fallback for source record definitions. Internal structural shapes remain
representation metadata. Nominal identity, aliases and specialization publication
use the shared definition/capture model. Operation signature compatibility remains
a separate explicit rule, not general structural type equality.

The coherent migration is committed without the local architecture audit or
for-later note. This closes the branch objective; optional integrations skipped by
the ordinary local suite retain their existing environmental requirements.

Audit evidence: syntax tests reject declaration-owned generic parameters; global
generic tests cover canonical identities, captured prefixes and speculative ID
reuse. Types 302–320 and 348 cover aliases, named/imported signatures, nested
choices and contextual construction in native, VM and #run execution. Interactive
tests cover persistent Init evidence, partial targets, static providers, defaults
and rejected submissions. Operation compatibility is centralized in types.zig;
inline contextual signatures reuse required identities without equating unrelated
nominal types. LLVM inspection of contract case 353 confirms direct calls to the
selected conformances; native and VM execution both succeed.

## Resolution cleanup

Constructor inference now retains both Target and Args through the selected Init
call. Input signatures reuse their type fields and captured defaults; only output
entry initializers that differ from the result type need separate fields. Candidate
matching reads the same defaults without synthetic marker nodes. Scalar signature
wrappers are removed and negative cases cover specialized inputs and outputs.

Participant inference and dispatch share the transactional implementation catalog,
including concrete and generic templates. SelectedOperation defines the captured
argument prefix used both to instantiate operations and recognize their evidence;
prefixes already stored in one range are reused without an intermediate allocation.

Signature inference, contextualization and final checking remain separate stages:
inference binds patterns, contextualization supplies identities to definition
literals, and final compatibility checks field names/types and defaulted extra
inputs. Named types preserve nominal equality. Combining these algorithms would
mix their responsibilities; the concrete operation compatibility rule remains in
types.zig.

Cleanup validation passes: 2,446 program cases and 1,045 Debug internal tests,
with 11 optional program skips and one internal skip. Official formatting and
zig fmt checks pass. The transactional catalog test includes concrete and generic
entries and exercises allocation failures and rollback.

Record literals and function arguments now share matchRecordFields for field/type
compatibility and completeRecordFieldsWithContext for defaults and contextual
construction. Call adapters add lexical capability lookup; output assignments use
the ordinary value checks and initialization analysis. Contract signature
compatibility remains a separate relation. Regression coverage rejects unknown
record/call fields even when every declared field has a default, and compares
record construction with named inputs and outputs across native/VM/#run execution.

Shared-record validation passes the complete program suite (2,447 passed,
11 optional skips), the complete prior internal set (1,045 passed, one skip) and
the added unknown-field regression. The cross-context fixture also passes native,
VM and #run execution; LLVM inspection confirms record inputs and outputs.
