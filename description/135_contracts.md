# Functions, contracts, and conformance

## Operation identities

An ordinary function has one identity in its module namespace. It can be generic,
but its name cannot be overloaded, including by changing compile-time parameter
count or types. Ordinary definitions place their `#(...)` parameters on the value after `:=`:

```argi
square := (.value: Int32) -> (.result: Int32) {
    result = value * value
}

identity := #(.T: Type) (.value: T) -> (.result: T) {
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

The reserved keyword `implement` supplies a contract's operations and associated
elements for a tuple
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

Members may also use a specialized definition directly, for example
`.copy = copy_value#(T)`. Its compile-time arguments retain the implementation's
lexical bindings. Function-value expressions are resolved through the ordinary
captured-expression machinery; pending aliases do not force premature evaluation.

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

Incremental sessions distinguish a registered operation signature from its
completed body. Registration alone does not freeze the body's conformance
choices. The first selected use completes and checks the body within one
semantic transaction. Lexical names retain their definition context; concrete
participants can select evidence introduced after that definition. Once
completed, the specialization keeps its body and selected evidence. New type
arguments may produce new specializations; materializing one never rewrites
another. Rejected materialization restores the pending signature and publishes
neither body proofs nor executable units.

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

An associated family is also a compile-time value. For example, passing
`Factory#(Owner).Args` to a family parameter preserves the selected definition
and its captures. The known participants select the conformance first; the
associated value does not infer an otherwise unknown participant.

## Standard operations

Construction uses `Init#(Target, Args)`. Both participants are concrete types;
Args is the nominal input record and retains its defaults. The associated Result
must be Target or an Errable containing Target. The fixed requirement is
`.init: Args -> (.result: Result)`.

`T(...)` fixes the target and infers the remaining participants from applicable
input signatures and lexically assumed arguments. Implementation parameters, including
static allocator types, must be determined by those participants. Several Init
conformances may share a target. Different inferred argument types require
qualification; specificity only compares conformances for the same complete tuple.
Return types never select construction. Untyped call literals receive their
nominal context from candidate signatures, not structural type identity.

Eligible types without a custom Init retain structural construction. Alternative
factories may still use explicitly named functions. Initializer behavior and
compiler-managed storage initialization/cleanup remain separate responsibilities.

Unqualified calls can infer participants from implementation-owned inputs,
including ordinary generic aliases and operation-local compile-time parameters.
Inputs must identify a unique operation and participant tuple; an expected output
type does not disambiguate either. Signature probes discard their semantic
effects, and preserve any newly inferred nominal types until actual selection.

Conversion uses `Convert#(Source, Target)` and its associated `Result`. The result
must be `Target` or an `Errable` containing it. Explicit conversion syntax is
`convert#(.to: Target)(.value = source)`, usually written as
`source | convert#(.to: Target)(_)`. No separate TryConvert is needed.

`Deinit#(T)` provides an infallible mutable-reference operation and can use
available assumed capabilities. Automatic cleanup retains compiler checks for
initializedness, ownership transfer, reference invalidation and double destruction.
Structural destruction remains available where no custom Deinit is required.

Operators identify standard contracts such as Add, Multiply and Equal. Their
conformances use the same participant dispatch and obey explicit copy, move and
reference rules.

Binary arithmetic contracts select by their two operand types:

```argi
Add#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .add: _
)
```

Each implementation supplies its operation signature. Its ordinary inputs include
both operands and any auxiliary capabilities. An allocator provider can be a
compile-time parameter of that callable, inferred from an explicit or lexically assumed input after the conformance has been selected. It does not distinguish
conformances. The operation returns `(.result: Result)`; Result never selects an
implementation. Borrowed operands use reference participants and explicit
reference arguments. Concrete and specialized generic expressions share this
selected-evidence path.

Equality uses `Equal#(Left, Right)` with an `equal` operation taking the two
operand types directly and returning `(.ok: Bool)`. Borrowed equality uses
reference participants, such as `Equal#(&Key, &Key)`. Auxiliary inputs belong
to the operation signature and cannot distinguish conformances for one tuple.
The `!=` symbol negates the same selected operation and evaluates it once.
Bundled StringView, time values, Path and semver comparisons use Equal; auxiliary
capabilities are ordinary inputs, including in generic bodies.
Both addition and equality require explicit references for borrowed operands;
there is no implicit receiver address. Legacy operator declarations and their
metadata registries are removed. Arithmetic symbols select Add, Subtract,
Multiply, Divide or Remainder. Bundled scalar conformances use private
representation hooks; primitive lowering happens after evidence selection and
preserves constant expressions. It never replaces a custom implementation.
Scalar equality also selects Equal evidence before primitive lowering, preserving
IEEE NaN behavior and evaluating != once.
Choices without payloads use the same selected-evidence path to compare tags.
The operands must have the same type; matching variant names do not make two
independent nominal choices interchangeable. Choices with payloads require their
own equality implementation.

Ordered comparisons use two contracts with ordinary Left and Right participants:

- `Compare#(Left, Right)` requires `compare(.left: Left, .right: Right)` returning
  `(.order: Ordering)`. Ordering has less, equal, greater and unordered variants.
- `CompareRelations#(Left, Right)` requires Compare and the four Bool operations
  less_than, less_than_or_equal, greater_than and greater_than_or_equal.

A generic implementation of CompareRelations consumes Compare evidence and
interprets its result through ordinary core functions. More specific implementations
replace that complete predicate implementation. Contracts have no optional operations
or default bodies. Operators select CompareRelations using the actual operand types;
references must be passed explicitly. These contracts have no Args participant and
require no inference through auxiliary argument records or associated results.
Primitive scalar implementations specialize the predicates, preserving direct LLVM
comparisons without computing the complete classification. All four derived
predicates return false for unordered; they never derive inclusive comparisons by
negating strict comparisons. Compare is infallible; fallible algorithms use explicit
operations outside these standard contracts.

`TotalOrder#(Left, Right)` requires Compare and promises a total ordering, including
that compare never returns unordered. Mathematical consistency, transitivity and
coherence with any corresponding Equal implementation remain implementer obligations.
Integers, Bool and UnicodeScalar provide this evidence; floating-point types do not.

C enum and C function-pointer equality also select Equal evidence. Their private
representation classification is compiler-provided; it does not provide ordering
or bypass operation selection. Choice tag tests retain their control-flow representation.

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

## Declaration validation and body proofs

Registering an implementation checks its participants, associated elements,
operation signatures, declared safety clauses and conformance coherence. Its
body proofs may remain pending while the implementation is unused.

An executable build proves the bodies and safety promises of selected operations
and their dependencies. Automatic cleanup counts as operation use. Constructing
virtual evidence requires proving every operation supplied by that evidence,
even when no dynamic call follows. Reusing an ordinary function in several
implementations does not select their other operation identities or promises.

`argi check` validates unused concrete bodies and materialized specializations
as well. Editor diagnostics use this exhaustive mode. Generic bodies with unknown
participants still require proof when their concrete specialization is selected.
No pending safety promise may justify executable code without its body proof.

## Implementation status

The compiler accepts unique ordinary declarations with `:=`, scoped contract
operation signatures, and concrete `implement` declarations with inline bodies
or ordinary-function aliases. Qualified operation calls preserve their contract
identity through generic function specialization and select direct calls. Associated
Type and Int elements are bound to inline bodies; signature, visibility, extension
ownership are checked at registration. Selected operations have their declared
safety guarantees proved; exhaustive checking also validates unused operations.
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
Symbolic arithmetic equivalence and other structural patterns remain pending.
Construction, destruction and explicit conversion use Init, Deinit and Convert.
Integer conversions and reference-address observation use selected Convert
evidence; numeric type-call conversions are rejected. Arithmetic and equality
operators select standard contract evidence. Composition preserves dependency
operation identities; joint virtual evidence remains pending.
Unary contracts with explicit participants can construct virtual handles using
selected implementation evidence when their associated elements are fully bound. Qualified
unary calls use `Contract#().operation(...)`; a concrete input infers the
participant and a virtual handle supplies its hidden participant. Their tables reuse the existing representation and declared safety
checks, including mutable receiver permissions and fallible capability inputs.
Bundled OrderPolicy uses explicit policy and element participants, scoped inline
implementations and qualified calls throughout sort, binary search and priority
queues. Its former global less functions and unary conformance declarations have
been removed. Sort, binary_search and _sift_down use unique ordinary declarations.
Bundled HashPolicy uses explicit policy/key participants and scoped query/hash/equal
operations that borrow keys throughout maps and sets. A single HashMap
implementation supports copyable and noncopyable elements.
Generic function instance validation shares the same tuple-aware contract check
used during selection.

Ordinary declarations enforce one identity per module, regardless of declaration
spelling or compile-time arity. Ordinary lookup checks applicability without
specificity ranking; multiple applicable identities require qualification.
Generic probes retain declaration identities so the same declaration is counted
once. Legacy Abstract declarations, satisfies/implements relations, defaultsto,
implicit Self and unscoped operation signatures are rejected with migration
diagnostics. Conformances use explicit operation bindings exclusively; static
calls and virtual tables select the same evidence. Functions declare their own
compile-time parameters and contract bounds. Module lowering creates no hidden
contract parameters or imported normalization derivatives. Earlier conformance
and default tables have been removed. Runtime values require concrete types or
explicit virtual handles; conformance never changes a field's representation.
Virtual and to_virtual use `.contract` or positional arguments; the former
`.abstract` label is rejected. Unknown argument names are checked before
contextual inference.

BufferReading scopes complete input-buffer reads. Its generic Reader fallback
copies bytes through read_byte, while File and TcpConnection select native block
algorithms and their associated error result types. A fixed Virtual#(Reader)
wrapper can participate in a static adapter conformance; the adapter invokes the
handle's frozen Reader operations. TCP writes reuse the common BlockWriter
write_all algorithm instead of a competing ordinary specialization.

Bundled Reader uses scoped implementations for files, process streams, TCP,
memory cursors and buffered/limited adapters. Its former global read_byte
family is removed. Bundled Writer likewise uses scoped write_byte/flush
implementations for files, process streams, TCP, memory cursors and buffered
adapters. Formatting, terminal output and error tracing call those identities.
Terminal and logging flush helpers remain unique ordinary functions.

Bundled ErrorTracer uses explicit tracer participants and scoped add_context,
reset_context and report operations. Noop, fixed-buffer and custom fixture
policies supply selected evidence. Context convenience functions have unique
names for views and text; the former global operation family is removed.

Allocator and Deallocator use explicit provider participants and scoped
implementations, including physical allocation cleanup. Allocation retains
selected virtual Deallocator evidence and authenticated acquisition bounds.
Byte requests use the unique allocate_bytes helper; typed allocate#(T) requests
use an optional count defaulting to one.

Unqualified scoped operations infer participants from inputs and check the
selected associated signature. Applicable contract identities and applicable
ordinary functions compete by identity, never by cross-contract specificity.
Multiple applicable identities require explicit qualification. Static and
generic bodies share this lookup; unary virtual inputs retain their identity.

Scoped requirement inputs use ordinary defaults and lexical assumptions.
Selection infers participants from explicitly supplied or assumed input fields,
including unary virtual evidence. A missing input never supplies an inferred
type or extends a caller signature. Conformance ambiguities remain diagnostics
after speculative selection rolls back.

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
OrderPolicy supplies owning collection comparisons without consuming
elements. Bound unary virtual types retain their fixed interface evidence when
passed through ordinary generic functions or static contract implementations.

Explicit contracts can require other participant contracts in their bodies. The
selected conformance must satisfy those dependencies, including named associated
restrictions. Dependencies retain their operation identities; implementations do
not redefine inherited operations. Named associated constraints infer generic
leaves only after participants select the evidence, without using a desired
result to select an implementation.

Collection indexing now follows this model: MutableIndexable requires Indexable
and supplies only writable indexing. Resizable uses collection and allocation
provider participants for growth, while its Removable dependency supplies
allocation-free removal under its own unary identity. Generic collection
algorithms preserve their collection type and derive element constraints from
selected Item evidence. Validation of newly selected evidence joins ordinary
resolution and cleanup before the final graph is published.

ArgumentSource now uses an explicit Source participant and scoped length/get
operations. Native Arguments and CliArgumentViews share those identities through
static generic consumers and selected virtual tables. Single-output operation
labels remain accessible on both direct and virtual calls, including in
parameterized bodies. The source protocol and CLI view adapter live separately
from option-tokenization and schema code.

Generic operation aliases infer their ordinary function parameters from the
selected requirement's input signature. A named alias can retain a completely
or partially specialized function value; its captured arguments stay fixed, and
only remaining parameters are inferred. Reuse preserves the producer identity
and `once` restriction. No second overload search or result-directed inference
occurs. Selected bounds and result compatibility remain checked. Equivalent
generic implementation patterns
and extension ownership are checked even for dormant templates.

ImplicitlyCopyable and InfalliblyCopyable now have explicit Value participants.
The former grants duplication permission; the latter owns the explicit copy
operation. Implicitly copyable types receive a generic infallible implementation.
Ownership recognizes declared copy capabilities independently of global function
names, so an explicit owning copy operation never grants implicit duplication.
FalliblyCopyable now selects the value and allocator provider jointly. String,
Path and DynamicArray provide scoped operations; array copying has one generic
implementation and preserves the element's associated reasons and tracer.
Ownership queries these conformances rather than functions named copy.

The standard Init contract now owns canonical construction for migrated types.
Type calls select Init evidence, complete its Args record and invoke its init
operation; Result must be the target participant or one bundled Errable containing
it. Concrete and explicit generic calls, including parameterized bodies, share
this route. Closed anonymous Args records retain ordinary field defaults; generic
argument shapes retain ordinary defaults and lexical assumptions. Failed construction
probes roll back evidence and generic side effects.

Initializer safety and projected output dependencies recognize selected Init
operation bodies without a second constructor registry. Owning results still
receive automatic cleanup and borrowed results retain their input dependencies.
The legacy initializer syntax and family indexes have been removed. Constructor
selection uses contract participants, including Args, and never infers nominal
parameters from Result. Structural construction remains available for types
without Init.

All declared constructors in bundled core and official more modules now use
Init. This includes native capabilities, allocators, streams, collections, text,
codecs, Python owners and matrix/vector owners. Single-use capabilities reuse
ordinary once functions as their init members; their reachable-entrypoint
restriction survives scoped operation wrappers. Alternative scaled or validated
construction paths use named factories. Compiler fixtures also use Init; one negative fixture explicitly checks the
migration diagnostic for the retired declaration syntax.

The standard Deinit contract now selects static cleanup through the same scoped
evidence as explicit deinit calls. Its self input is consuming. Generic and
specialized conformances, ordinary operation aliases, imported owners and nested
structural cleanup share that route. A lifecycle wrapper gives the selected
operation destruction semantics without changing a reused ordinary function.
Auxiliary capability inputs must appear in the operation signature and are
supplied explicitly or through the caller's lexical assumptions.

Bundled Deinit implementations include allocation receipts and backing
allocations, arena owners/domains, collection shape markers, fixed tracers, native
process/network/directory owners, terminal endpoints, atomic cells and cancellation
sources. All bundled core, official more and compiler fixture destructor
declarations use Deinit. The old syntax, nominal associations, family indexes
and ordinary-function fallback have been removed. A negative fixture checks the
migration diagnostic. Ordinary function names confer no destruction semantics.
Bundled generic collection destructors use the stored
deallocation evidence without separate allocator inputs.

Even an empty destructor requires an initialized owner. Unknown pointer inputs
keep symbolic consumption identities separately from their conservative shared
borrow dependency. Copies retain identity, joins preserve possible consumption and
loop convergence compares both state and identity. This creates neither concrete
pointee storage nor ownership; actual caller overlap checks remain unchanged. Whole-receiver
destruction removes obsolete post-values of owned fields; it does not authorize
destruction of storage reached through borrowed reference fields. Virtual Deinit
remains rejected because consuming an erased receiver needs runtime cleanup
identities, which the current evidence representation does not provide.


Numeric classification uses explicit `Int#(Value)`, `UInt#(Value)` and
`Float#(Value)` conformances. These marker contracts do not provide arithmetic
operations or a default runtime representation. Color records use `Float32`
explicitly instead of the old `Float defaultsto Float32` mechanism.

Generic implementation ownership recognizes closed nominal participants as well
as nominal applications. A local concrete participant can establish ownership
when another participant remains generic; foreign nominal participants do not.

## Numeric writer values

`WriteValue#(Stream, Value)` declares an associated Result and a scoped
`write_value(.self: $&Stream, .value: Value)` operation. The unique ordinary
`write(.self, .value)` function selects this evidence and returns its Result.
Text returns Errable containing Void; buffers return counts. Native TCP writes
preserve socket_write_failed and partial progress. File buffer writes specialize
the general Writer byte algorithm without altering its error protocol.
Participants are inferred from the inputs, never the associated result. The
ordinary entry explicitly moves owning values and results, preserving cleanup
obligations when a custom protocol transfers ownership.

Numeric stream formatting uses the same identity. Bundled numeric
conformances require Writer for the stream and reuse one integer or float
encoding algorithm without allocation. A nominal stream may specialize a
conformance for one concrete value type. Qualified callers provide Stream and
Value explicitly, including in generic forwarding functions. Virtual Writer
participants use the same selected formatting implementation and their saved
writer evidence for byte operations.

The result preserves stream_write_failed and stream_flush_failed. Formatting
stops on the first failed byte, keeps the written prefix and never requests
an implicit flush. Numeric print delegates to this operation before writing its
terminator. The former numeric write and writer format_into ordinary families
are removed. Text/buffer/file/TCP write overloads are also removed. String formatting and readonly/mutable views use the scoped protocols described
below.

## Ordinary-family migration

Numeric limits use IntegerBounds evidence behind the unique integer_limits
entry. Private IEEE encoding/replacement uses _FloatRepresentation; these
operations remain representation-specific, not a public Float extension hook.
StringFormatting selects value and allocator provider jointly; unique format and
format_into entries reuse selected render/append operations. Concatenation
provides the unique concat entry for borrowed strings and string views.

ContiguousView associates the base pointer type and shares checked subranges
without erasing mutability. CollectionLength/CollectionCapacity select nominal
collection queries. ByteCursor scopes stateful cursor queries, while *_uint*_at
operations name independent indexed byte access. Viewable and TextBytes retain
borrowed text projections. TimeCompare, NanosecondCount and ReadLimit replace
ordinary query overload families without selecting by result type.

These migrations remove individual ordinary families. Global ordinary candidate
selection and legacy contract syntax remain transitional until all consumers and
fixtures have moved; their final removal is a separate required completion gate.

Optional Python conversion and invocation also use selected contract evidence.
Numeric transfers share scalar/view metadata rather than ordinary overloads.
Generic default inference may learn a direct participant from a known typed
default or a unique local zero-input concrete factory's declared signature. This
reads an input value's type without executing the factory or using the caller's
expected result. It never infers from cached generic specializations. Factories
execute only when the default is actually used, with ordinary safety and cleanup.

TestEquality scopes assertion diagnostics. The ordinary expect_equal entry is
unique; closed numeric/text conformances specialize the generic equality-based
implementation. External nominal values can provide their own checked assertion
operation. HashPolicy associates one canonical query representation for stored keys;
map lookup contracts share that representation without retaining query inputs
in lookup results.

Closeable selects resource closing through close_resource, with an associated
Result preserving each error protocol. Its unique ordinary close entry forwards
the selected operation and its safety effects without assuming success. OpenState supplies the unique is_open query returning ok: Bool.
Files, process streams, TCP/UDP handles and temporary directories reuse their
native close algorithms. Retryable temporary-directory failure retains its handle.

For implementation ownership, readonly and mutable references preserve the
nominal owner's right to extend a participant. This applies equally to closed
participants and generic reference patterns. It does not grant extension rights
through structural fields or arbitrary generic type arguments, and references to
foreign types alone grant no extension rights.

The semver library supplies Viewable for borrowed VersionView, StringFormatting
with the selected allocator Provider, and WriteValue by delegating to the stream's
StringView evidence. It exposes no separate format/view overloads. Writing a
version preserves the stream's selected Result, including counts or fallible writes.

Queue and QueueInsertion scope removal and insertion without ordinary overloads.
Queue associates Item and its selected removal Result, preserving optional heap
results and bounded-ring Errable results. QueueInsertion selects the allocation
Provider separately and retains lexical allocator defaults. Generic functions
can forward the selected removal result without imposing one representation.

Nominal input matching uses the declaration's compile-time parameter order for
ordinary generic functions and operation aliases, as it does for conformances.
Positional and reordered named type arguments bind the same parameters; output
types do not supply bindings. Shared argument lookup removes separate matching
rules for these forms.

Unary contracts can declare storage domains. An implementation supplies their
concrete paths after its members, for example:

```rg
Source#(.Value: Type): Contract = (
    domain storage
    .get: (.self: &Value) -> (.value: &Int32)
        where depends_on(value, self, self.storage)
)
implement#(.Tag: Type) Source#(Cell#(Tag)) (
    .get = get_cell
) where { storage(self.storage) }
```

Static calls and virtual construction resolve those paths from the selected
conformance. The existing ownership proofs reject missing, invalid or aliased
domains. A domain mapping supplies no storage acquisition permission. Contracts
with multiple participants still require an explicit domain receiver model.
Virtual inputs retain the declared domains even before any concrete handle is
constructed; checking an interface does not depend on available implementations.

A unary virtual interface may bind associated types and constants. Every
associated element must be fixed in the interface; the concrete selected
conformance must match it when the handle is built. Different bound interfaces
retain separate operation tables and safety identities. Runtime calls use those
fixed signatures and implementations without rerunning multiple dispatch.
