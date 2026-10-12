# Polymorphism

Argi combines several mechanisms for code that works with different types:

- Compile-time polymorphism:

  - [Compile-time parameters](132_generics.md) specialize types and functions
    for concrete arguments.

  - [Multiple dispatch](131_multiple_dispatch.md) lets operations on different
    data types share a name. The compiler considers all input types, rather
    than selecting a method through one receiver.

  - [Contracts](135_contracts.md) state capabilities and relations among
    participant types. Explicit `satisfies` declarations select conformances
    and determine associated elements. Static calls are specialized.

- Run-time polymorphism:

  - [Virtual types](134_virtual_types.md) request runtime dispatch through an
    contract while preserving selected operations and conformance evidence.

  - [Choice types](12_choice.md) hold one of a known set of alternatives.
    `match` selects behavior according to the active variant.

Compile-time specialization suits algorithms and collections whose concrete
types are known. It permits direct calls and optimization for each type, but
many specializations can increase code size. `Virtual` can represent
heterogeneous values behind one interface, at the cost of indirect calls.

> [!IMPLEMENTATION]
> Contracts support concrete participant tuples with associated types and
> constants, checked operations and static safety proofs. Legacy
> [abstract types](133_abstract_types.md) retain unary generic and virtual behavior
> during migration. Associated type projections use `Contract#(A, B).Result`.
> Generic tuple specialization, associated constant projections and joint virtual
> evidence are pending.
