# Contracts and conformance

A `contract` declares capabilities and relations among one or more participant
types. It specifies required operations, associated types and compile-time
constants, and restrictions connecting them. No participant has a privileged
`Self` role. Unary contracts express individual capabilities; multi-participant
contracts express relations such as a product between two matrix types.

Contract parameters use Argi's existing `#(...)` compile-time parameter syntax.
There is no separate angle-bracket generic syntax.

## Conformance and associated elements

A `satisfies` declaration establishes explicit conformance for a combination of
participants. For one contract and a concrete participant tuple, the selected
conformance uniquely determines its associated elements. A matrix product's
result type may differ from either operand.

Conformances can be generic or specialized. Resolution considers applicable
conformances, selects the uniquely most specific one, and rejects incomparable
maximal candidates. Associated elements come from that selection. A specialized
conformance may change both the required result type and the applicable algorithm.

Participants select conformance; associated elements are obtained from it.
Resolution does not search backwards from a desired associated result to infer
participants. Generic associated projections remain symbolic until sufficient
participant information is known.

> [!QUESTION]
> Type projections use `Product#(A, B).Result`. Exact specialization rules remain
> to be settled. The concrete participant syntax below is the current
> implementation surface and uses existing compile-time parameters.
> Restrictions do not require a general constraint solver or arbitrary inference.

## Operations and dispatch

Contracts refer to existing function families. They introduce neither a function
namespace nor independent method implementations. Ordinary multiple dispatch
selects an operation using its input types.

The selected conformance fixes associated elements and restrictions. Operation
resolution must select an implementation unambiguously and then check that its
signature and safety effects satisfy those promises. An incompatible result is
an error; the expected result cannot hide an ambiguous operation or cause fallback
to a less specific implementation.

Conformance proves the expressed contract, not the mathematical correctness of
an algorithm. Adding a function specialization cannot silently contradict the
associated elements of a selected conformance.

> [!QUESTION]
> Module visibility, permitted external conformances, and extension rules must
> define a stable resolution context. In particular, imported declarations must
> not silently alter the associated meaning of already checked generic code.

## Generic code

Generic algorithms state their required contracts rather than depending on a
particular representation. Their bodies use the operations and associated
elements guaranteed by those contracts.

Once participants are concrete, the compiler selects conformance, resolves its
associated elements, selects compatible operations, and specializes the code.
Contracts and restrictions are checked at compile time. Constraints can compose
contracts, compare associated types, and relate compile-time constants without
requiring inverse inference of arbitrary types.

## Virtual evidence

`virtual` hides concrete participant types while retaining values and evidence
of their joint conformance. Construction takes place where those types are known.
It selects conformance and operations, resolves associated elements, and checks
ownership, loans, aliasing and storage effects before erasing representation.

Dynamic invocation uses the operations selected at construction. It performs no
new multiple dispatch. The evidence remains tied to the packaged participants.

Unary borrowing handles can retain the existing object pointer and operations
table representation without allocation or ownership transfer. A contract
relating several hidden types requires a joint package: separately virtualized
values provide no evidence that their combination satisfies that relation.
Not every contract must be virtualizable.

Dynamic inputs and outputs need usable representations without knowing hidden
types. A result can have a known layout, use caller-provided storage through an
explicit protocol, or be packaged with its own evidence. No implicit allocation
or automatic conversion to a common representation follows from virtualization.
Different virtual packages need not share the same hidden associated type.

Safety evidence retains the dependencies and effects of every participant,
including relations between participants. Erasure cannot weaken lifetime,
ownership or aliasing obligations. A returned loan still depends on its concrete
referents and their storage generations.

## Concrete participant syntax

Declare associated parameters on the contract name and participant parameters
on the `contract#(...)` marker. Standalone `satisfies` supplies the participant
tuple first, followed by its associated arguments:

```rg
Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

satisfies Product#(Row, Column) = (.Result: Int32)

multiply(.left: &Row, .right: &Column) -> (.value: Int32) := {
    value = left&.value * right&.value
}
```

Participants are named type parameters, including when there is only one.
Requirements use those names directly; `Self` is rejected. Associated parameters
may be types or integers and may have bounds referencing participant parameters.
Both groups are registered before their bounds are lowered. Conformance arguments
use the usual named or positional compile-time syntax; omitting `= (...)` is valid
when the contract has no associated parameters.

The complete concrete tuple identifies a conformance. Reordering named arguments
does not create another identity; repeating a tuple is an ambiguity even if its
associated arguments differ. Reversing distinct participant types creates a
different tuple. Participant types may themselves be generic instantiations.

Conformance checks concrete operation signatures in the declaring module's
ordinary visibility context, then checks associated outputs and safety promises.
Its operations are analyzed even when no executable root calls them, so unused
conformance declarations cannot bypass safety checking. Imported contracts keep
their defining declaration identity. Tuple evidence is compile-time metadata;
ordinary calls keep their existing lowering and allocate no evidence at runtime.

Associated types can be queried as `Product#(Row, Column).Result`, including
named participant arguments and imported contract identities. The query selects
the concrete tuple evidence and preserves the associated type's nominal identity.
Missing conformances, unknown members and integer members in type positions are
errors. Dependencies between associated type projections are resolved before
generic records are materialized and operation signatures are checked; unresolved
cycles are errors. Tuple uniqueness is checked again after resolving participant
projections.

A generic function can return `Product#(A, B).Result` when ordinary input
inference or explicit compile-time arguments determine `A` and `B`. The
projection remains symbolic in parameterized IR and resolves when the function
is instantiated. It does not infer participants from an associated result.
Until tuple constraints are supported, the function is checked for each
instantiation rather than proven against a generic tuple contract at declaration.

Associated integer constants can be queried in compile-time type arguments:

```argi
Shape#(.Count: Int): contract#(.Input: Type) = ()
satisfies Shape#(Cell) = (.Count = 2)
Box#(.T: Type): Type = (
    .values: Array#(.n = Shape#(T).Count, .t: Int32)
)
```

These projections remain symbolic in generic type and function signatures and
resolve from the selected concrete conformance. Integer arithmetic can combine
projections with other compile-time expressions. Array dimensions must be
non-negative; division by zero and signed integer overflow are diagnosed.
Concrete projected type applications are persisted as syntax-free compile-time
expressions in frontend snapshots. They introduce no runtime evidence or lookup.
Integer projections are currently supported in type applications and explicit
compile-time call arguments in concrete and generic function bodies, including
constructor arguments. Ordinary runtime expressions and associated-value
assignments in `satisfies` declarations remain pending.

> [!IMPLEMENTATION]
> Explicit participant conformances currently require concrete tuples and
> concrete operation implementations. Generic conformances, specialized tuple
> selection and tuple bounds in generic
> functions remain pending. Storage domains, composition and virtual conversion
> of explicit participant contracts are rejected until joint mappings and evidence are
> represented. Unary compatibility syntax below continues to support the
> existing generic and virtual machinery independently.

## Unary migration syntax

Unary compatibility syntax retains its existing argument binding while sharing
the participant representation used by explicit contracts:

```rg
Readable#(.item: Type): contract = (
    read(.source: &Self) -> (.value: &item)
        where depends_on(value, source)
)

Cell#(.item: Type): Type = (.value: item)
Cell#(.item: Type) satisfies Readable#(item)

read#(.item: Type)(.source: &Cell#(item)) -> (.value: &item) := {
    value = &source&.value
}

consume#(.item: Type, .source_type: Type: Readable#(item))(
    .source: &source_type
) -> (.value: &item) := {
    value = read(source)
}
```

Here `item` is an associated parameter; it does not independently select another
participant. Functions remain ordinary declarations outside the contract.

> [!IMPLEMENTATION]
> Unary declarations now contain one implicit Type participant. Source `Self`
> lowers to an ordinary reference to that participant in parameterized IR; there
> is no separate abstract-self IR type. The compatibility adapter supplies the
> concrete or erased participant during instantiation. Legacy `Abstract` and
> `implements` remain accepted, including mixed
> composition. Generic conformances, associated type/value arguments, static
> safety checking and unary virtual handles retain their existing behavior.
> Requirements still use `Self`. Unary handles accept `Virtual#(.contract: Name)`
> and `to_virtual#(.contract: Name)`, as well as positional arguments and the
> legacy `.abstract` label; these spellings produce the same handle type.
> The source compatibility surface still differs from explicit participant tuples:
> arguments name associated elements, while the participant is implicit. Unary
> conformance selection and virtual evidence still use compatibility adapters;
> unifying those with tuple conformance selection remains pending.
> Bundled libraries and generated entry code use the canonical `.contract` label.
> Specialized tuple conformance selection and
> joint virtual packages are not implemented.
> Existing unary associated arguments remain unique per concrete type and
> contract; conflicting arguments are errors, not specialized conformances.
> Diagnostics still describe these internal declarations as abstracts.

`defaultsto` is a separate representation-default mechanism. It does not establish
conformance and is not part of the general contract model.
