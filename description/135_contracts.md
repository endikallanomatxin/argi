# Functions, contracts, and conformance

## Operation identities

An ordinary function has one identity in its module namespace. It can be generic,
but its name cannot be overloaded, including by changing compile-time parameter
count or types. Ordinary declarations use the existing `#(...)` parameter syntax:

```argi
square := (.value: Int32) -> (.result: Int32) {
    result = value * value
}

identity#(.T: Type) := (.value: T) -> (.result: T) {
    result = value
}
```

A contract is a static structure describing capabilities and relations among its
participant types. It has no runtime representation. Its operations are named
static members with their own identities; they are not stored function fields.
Two contracts can declare operations with the same member name without sharing
an operation identity. No participant is privileged as `Self`.

```argi
Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .multiply: (.left: &Left, .right: &Right) -> (.result: Result)
)
```

Contracts can declare operations, associated types/constants, type/value
restrictions, safety guarantees, and dependencies on other contracts. Dependency
composition preserves the original operation identities instead of duplicating
members under the composing contract.

## Implementations and specialization

`implement` supplies a contract's operations and associated elements for a tuple
of participants. It does not use an assignment after the contract application:

```argi
implement Product#(Row, Column) (
    .Result: Type = Int32
    .multiply = (.left: &Row, .right: &Column) -> (.result: Int32) {
        result = left&.value * right&.value
    }
)
```

Members can reuse a uniquely identified ordinary function:

```argi
implement Product#(Row, Column) (
    .Result: Type = Int32
    .multiply = multiply_row_column
)
```

Generic binders belong after `implement`, for example
`implement#(.T: Type) Copyable#(Box#(T)) (...)`. Applicable conformances are ranked
by structural pattern specificity. Select one uniquely most specific conformance;
reject equivalent patterns and incomparable maximal candidates. Return types
never select conformance. The selected conformance uniquely fixes associated
elements and required signatures. An incompatible signature is an error and does
not cause fallback to a less specific conformance.

An external implementation must be declared in the contract's defining module
or the defining module of a nominal participant. Validate visible overlaps
without giving source order or import order any priority.

## Calling operations

Qualified calls identify the operation explicitly:

```argi
result ::= Product#(Row, Column).multiply(&row, &column).result
```

Unqualified calls consider visible ordinary functions and contract operations.
Infer participants from inputs and explicit compile-time arguments. Participants
that cannot be inferred must be provided explicitly, without using expected
return types or arbitrary inverse inference through associated elements.

A contract identity is applicable if its participants can be established and a
conformance can be selected. If multiple identities are applicable, require
qualification. Never compare conformance specificity across different contracts.
After identifying the operation, select its conformance, resolve associated
elements, and check the call against the selected signature and safety promises.

Generic code retains symbolic associated projections, such as
`Product#(Left, Right).Result`, until participant bindings are available. Contracts
provide compile-time guarantees; specialization and monomorphization produce
ordinary concrete calls. Constraints are checks on known or inferred parameters,
not a general constraint-solving mechanism.

## Standard operations

Construction uses `Init#(T)`, with associated `Args` and `Result` and an `init`
operation. `T(...)` supplies fields of `Args`, including their defaults. `Result`
is `T` or an `Errable` containing `T`; eligible types without a custom Init retain
structural construction. Alternative construction uses explicitly named functions
or conversions instead of constructor overloads.

Conversion uses `Convert#(Source, Target)` and its associated `Result`. The result
must be `Target` or an `Errable` containing it. Explicit conversion syntax is
`convert#(.to: Target)(.value = source)`. No separate TryConvert is needed.

`Deinit#(T)` provides an infallible mutable-reference operation and can use
available assumed capabilities. Automatic cleanup retains compiler checks for
initializedness, ownership transfer, reference invalidation and double destruction.
Structural destruction remains available where no custom Deinit is required.

Operators identify standard contracts such as Add, Multiply and Equal. Their
conformances use the same participant dispatch and obey explicit copy, move and
reference rules.

## Virtual evidence and safety

Virtualization hides concrete participants while preserving values and selected
conformance evidence. At construction the compiler selects the conformance,
resolves associated elements and fixes the operation implementations. Dynamic
calls use that evidence; they do not repeat static multiple-dispatch search.

Several hidden participants require joint evidence. Independently erased values
do not establish a contract relating their hidden types. A joint package avoids
requiring a general runtime multiple-dispatch mechanism.

Not every contract must be virtualizable. Dynamic signatures need usable input
and output representations: known layouts, explicit caller-storage protocols, or
explicitly packaged results with evidence. There are no implicit allocations or
conversions to a common representation.

Conformance and virtual evidence preserve lifetimes, ownership, aliasing,
capability dependencies, hidden-storage effects and relationships between
participants. Type erasure never weakens these obligations. Contract checking
proves the expressed promises, not mathematical correctness of an algorithm.

## Implementation status

The compiler accepts unique ordinary declarations with `:=`, scoped contract
operation signatures, and concrete `implement` declarations with inline bodies
or ordinary-function aliases. Qualified operation calls preserve their contract
identity through generic function specialization and select direct calls. Associated
Type and Int elements are bound to inline bodies; signature, visibility, extension
ownership and declared safety guarantees are checked, including unused operations.
Frontend snapshots preserve these declarations and operation identities.

The frontend preserves `implement#(...)` binders in participant patterns,
associated definitions and inline body templates. Unique applicable generic patterns can be selected from concrete participants,
with associated elements and inline bodies instantiated from those bindings.
Repeated parameter occurrences enforce equality. Generic selection compares participant tuples by symbolic substitution for
parameter leaves, closed types, references and arrays with literal or parameter
lengths,
including repeated-parameter equalities. Reference matching preserves mutability
and recursively infers referent parameters.
Strictly less specific candidates are discarded; equivalent and incomparable
maximal candidates are ambiguous. Integer substitutions preserve repeated array-length equalities across participants.
Nominal application patterns match declaration identities and recursively bind
type and integer arguments in declaration order, including named arguments.
Symbolic arithmetic equivalence and other structural patterns remain pending. Standard construction, conversion, destruction
and operator migration, composition and joint virtual evidence remain pending.
Unbound unary contracts with explicit participants and no associated parameters
can construct virtual handles using selected implementation evidence. Qualified
unary calls use `Contract#().operation(...)`; a concrete input infers the
participant and a virtual handle supplies its hidden participant. Their tables reuse the existing representation and declared safety
checks, including mutable receiver permissions and fallible capability inputs.
Bundled OrderPolicy uses explicit policy and element participants, scoped inline
implementations and qualified calls throughout sort, binary search and priority
queues. Its former global less functions and unary conformance declarations have
been removed. Sort, binary_search and _sift_down use unique ordinary declarations.
Bundled HashPolicy and BorrowedHashPolicy also use explicit policy/key
participants and scoped hash/eql implementations throughout maps, sets and
iteration. Their global operation families have been removed. Borrowed integer
hashing reuses the corresponding value-key implementation.
Generic function instance validation shares the same tuple-aware contract check
used during selection.

The compiler still contains transitional global overload resolution and earlier
conformance syntax for other contracts. Removal obligations are tracked in
`plan/contract_dispatch_refactor.md`; existing `Abstract`/`satisfies` adapters are
not part of the intended final language.

> [!IMPLEMENTATION]
> Bundled Reader uses scoped implementations for files, process streams, TCP,
> memory cursors and buffered/limited adapters. Its former global read_byte
> family is removed. Bundled Writer likewise uses scoped write_byte/flush
> implementations for files, process streams, TCP, memory cursors and buffered
> adapters. Formatting, terminal output and error tracing call those identities.
> Terminal and logging flush helpers remain unique ordinary functions.

> [!IMPLEMENTATION]
> Bundled ErrorTracer uses explicit tracer participants and scoped add_context,
> reset_context and report operations. Noop, fixed-buffer and custom fixture
> policies supply selected evidence. Context convenience functions have unique
> names for views and text; the former global operation family is removed.

> [!IMPLEMENTATION]
> Allocator and Deallocator use explicit provider participants and scoped
> implementations, including physical allocation cleanup. Allocation retains
> selected virtual Deallocator evidence and authenticated acquisition bounds.
> Byte requests use the unique allocate_bytes helper; typed allocate#(T) requests
> use an optional count defaulting to one.

> [!IMPLEMENTATION]
> Unqualified scoped operations infer participants from inputs and check the
> selected associated signature. Applicable contract identities and applicable
> ordinary functions compete by identity, never by cross-contract specificity.
> Multiple applicable identities require explicit qualification. Static and
> generic bodies share this lookup; unary virtual inputs retain their identity.

> [!IMPLEMENTATION]
> Scoped requirement inputs retain lexical reach defaults. Unqualified operation
> selection can infer direct participants from visible capability bindings and
> field paths, including unary virtual evidence. A missing capability does not
> supply an inferred type. Selected calls materialize the requirement defaults
> through the ordinary reached-argument path. Conformance ambiguities remain
> diagnostics after speculative selection rolls back.

Bundled iteration protocols now use explicit collection/state participants and
associated `Item`/`IteratorType` elements. `for` calls the selected conversion,
`has_next` and `next` identities directly; unrelated ordinary functions with
those names cannot alter loop lowering. Synthetic iterable and iterator owners
remain in the surrounding lexical scope, including borrowed and consuming
loops. Generic code can use the same scoped operations without erasing the
iterator's type or allocating an implicit virtual result.

BlockReader and BlockWriter use explicit stream participants and selected virtual
evidence. Their static/virtual algorithm copies have been consolidated.
StreamTransfer scopes the general and buffered endpoint implementations to one
two-participant identity; specialization never chooses between unrelated contracts.
BorrowedOrderPolicy supplies owning collection comparisons without consuming
elements. Bound unary virtual types retain their fixed interface evidence when
passed through ordinary generic functions or static contract implementations.

Explicit contracts can require other participant contracts in their bodies. The
selected conformance must satisfy those dependencies, including named associated
restrictions. Dependencies retain their operation identities; implementations do
not redefine inherited operations. Named associated constraints infer generic
leaves only after participants select the evidence, without using a desired
result to select an implementation.

Collection indexing now follows this model: IndexableMutable requires Indexable
and supplies only writable indexing. Resizable uses collection and allocation
provider participants for growth, while its Removable dependency supplies
allocation-free removal under its own unary identity. Generic collection
algorithms preserve their collection type and derive element constraints from
selected Item evidence. Validation of newly selected evidence joins ordinary
resolution and cleanup before the final graph is published.
