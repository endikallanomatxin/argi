# Abstract types

Abstracts express static callable contracts. A concrete type declares an
explicit `implements` relationship, and matching functions satisfy the
contract. Concrete types may expose other operations as well. Abstracts
contain callable requirements and can compose other abstracts; they do not
declare instance fields.

A function input declared with an abstract is monomorphized for its concrete
argument type. Request runtime dispatch explicitly with
`Virtual#(.abstract: A)`; see [Virtual types](134_virtual_types.md).

## Declaration and defaults

`Self` inside an abstract refers to the implementing concrete type:

```rg
Animal : Abstract = (
    speak(.who: &Self) -> (.sound: Int32)
)
Dog : Type = (.voice: Int32)
Dog implements Animal

speak(.who: &Dog) -> (.sound: Int32) := {
    sound = who&.voice
}
Animal defaultsto Dog
```

`defaultsto` selects a concrete type when an abstract is used as a value's
specified type. Without a default, use a concrete type for that value.
A default does not turn ordinary abstract inputs into virtual dispatch.

## Associated parameters

The parameters of an abstract are compile-time information associated with the
implementing type. For each concrete pair `(Self, Abstract)`, resolution must
produce one unique argument vector:

```text
(Self, Abstract) -> [GenericArgValue]
```

They do not select among multiple implementations. Several composition paths
may prove the same implementation when they produce equal arguments; paths
that produce different arguments conflict.

Associated parameters are not limited to types. They use the same compile-time
argument domain as generics, so an abstract may associate both types and values
such as integer dimensions. For example, `AbstractMatrix#(.t: Type, .rows:
UIntNative, .cols: UIntNative)` associates all three values with each concrete
matrix type.

Inference is deliberately directional. The compiler first infers `Self`, then
resolves its abstract implementation, and finally binds or checks the
associated parameters. It never searches backwards from an associated
parameter to discover a possible `Self`. Relations that genuinely need several
independently selected types belong in multiple dispatch, with `where(...)`
reserved as a possible future constraint mechanism.

For example, resolving `FalliblyCopyable` for a type determines its unique
`.reasons` choice, while resolving `Iterator` determines its unique `.t`.

## Composition and shared concrete types

An abstract can include other abstract contracts alongside its own callable
requirements. Satisfying the composed contract requires satisfying each
included contract with consistent associated arguments.

Two independently abstract inputs need not have the same concrete type.
Use one constrained comptime type parameter when their types must match:

```rg
combine#(.t: Type: Addable)(.left: t, .right: t) -> (.result: t)
```

Interactions between independently selected concrete types use multiple
dispatch rather than reverse inference of abstract-associated arguments.
Contract checking and overload resolution must agree on which callable
implementation satisfies a requirement. See [Multiple dispatch](131_multiple_dispatch.md).

## Collection contracts

`Indexable`, `IndexableMutable`, `IndexableValue`, and `Resizable` describe
named collection operations, element types, and associated failure reasons.
They use ordinary abstract parameters and callable requirements rather than
library-defined bracket operators. See [Lists](161_lists.md) and
`core/lists/List.rg` for their contracts.

> [!IMPLEMENTATION]
> `DynamicArray` provides corresponding operations but does not yet declare
> an explicit `implements Resizable` relationship.

## Expressiveness checks

Library use cases should test whether abstracts express useful static
contracts. A matrix abstract can associate an element type and dimensions;
generic operations can then use that contract to check operand compatibility.
Being a matrix and being compatible with another matrix are distinct claims.
Approximate contract and operation examples are retained in
[the matrix exploration notes](../more/math/linear_algebra/abstract_matrix.txt).

> [!QUESTION]
> Can the abstract system express the same compatibility checks when operands
> have different concrete representations, such as sparse and dense matrices?
> Infer each concrete type first, resolve its associated element type and
> dimensions, then check their relationship. Demonstrate that a generic
> algorithm can use this contract without enumerating every representation
> pair or reverse-searching for an unknown `Self`.
>
> Selecting a result representation is a separate question: compatible shapes
> do not determine whether the result is sparse, dense, or another type. Nor
> is every representation closed under an operation. Use this case to evaluate
> whether existing bounds and multiple dispatch suffice or a small relational
> constraint mechanism is needed; do not assume the full case is implemented.

## Open design questions

> [!QUESTION]
> Define visibility and authorization for external `implements` declarations
> alongside cross-module overload lookup and orphan rules.
>
> [!QUESTION]
> Decide whether `where(...)` constraints are needed for relationships between
> several independently selected types. Keep associated-parameter inference
> directional rather than using a constraint to search for an unknown `Self`.
>
> [!QUESTION]
> Define whether any generic subtyping is intended. A relationship between
> `Int64` and an abstract `Number` alone does not establish that
> `Vector<Int64>` can be used as `Vector<Number>`.
