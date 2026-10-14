# Polymorphism

Argi combines several mechanisms for code that works with different types:

- Compile-time polymorphism:

  - [Compile-time parameters](132_generics.md) specialize types and functions
    for concrete arguments.

  - [Contract dispatch](131_multiple_dispatch.md) selects an implementation
    from a contract's participant tuple. Participants can describe input types
    or an explicitly requested destination type; no receiver is privileged.

  - [Contracts](135_contracts.md) state capabilities and relations among
    participant types. Explicit `implement` declarations provide operations
    and associated elements. Static calls are specialized.

- Run-time polymorphism:

  - [Virtual types](134_virtual_types.md) request runtime dispatch through a
    contract while preserving selected operations and conformance evidence.

  - [Choice types](12_choice.md) hold one of a known set of alternatives.
    `match` selects behavior according to the active variant.

Compile-time specialization suits algorithms and collections whose concrete
types are known. It permits direct calls and optimization for each type, but
many specializations can increase code size. `Virtual` can represent
heterogeneous values behind one interface, at the cost of indirect calls.

> [!IMPLEMENTATION]
> Contracts support concrete and generic participant tuples, specialization,
> associated types/constants, checked operations and static safety proofs.
> Construction, destruction, conversions and arithmetic/equality operators use
> selected contract evidence. Associated projections use `Contract#(A, B).Result`.
> Dependency composition preserves operation identities. Ordinary functions have
> one identity per module; legacy abstract syntax and global overload families
> have been removed. Joint virtual evidence remains pending.
