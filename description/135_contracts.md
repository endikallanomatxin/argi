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
> The declaration syntax separating participant parameters from associated
> elements, the spelling of associated projections, and exact specificity rules
> remain to be settled. They must integrate with existing compile-time parameters.
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

## Unary migration syntax

The first migration surface preserves the existing unary implementation model:

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
> `Name: contract` and `Type satisfies Name` currently use the unary abstract
> machinery. Legacy `Abstract` and `implements` remain accepted, including mixed
> composition. Generic conformances, associated type/value arguments, static
> safety checking and unary virtual handles retain their existing behavior.
> Requirements still use `Self`. Unary handles accept `Virtual#(.contract: Name)`
> and `to_virtual#(.contract: Name)`, as well as positional arguments and the
> legacy `.abstract` label; these spellings produce the same handle type.
> Participant tuples, associated declarations/projections, specialized
> conformance selection and joint virtual packages are not implemented.
> Existing unary associated arguments remain unique per concrete type and
> contract; conflicting arguments are errors, not specialized conformances.
> Diagnostics still describe these internal declarations as abstracts.

`defaultsto` is a separate representation-default mechanism. It does not establish
conformance and is not part of the general contract model.
