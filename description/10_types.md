# Types

Type names conventionally use `PascalCase`; value names use `snake_case`.
Types are checked during compilation. A named type has its own identity:
two independently declared types do not become interchangeable merely
because their fields match. Unnamed structural types may be compared by
their field structure. See [Structs](11_structs.md) and [Choice](12_choice.md).

Types are values that can be passed as compile-time parameters. For example,
`Array#(.n = 4, .t = Int32)` selects an array type using a length and an
element type. See [Compile-time parameters](132_generics.md).

## Type queries

`type_of(.value = expression)` obtains the type of an expression. `size_of`
and `alignment_of` query a type's size and alignment:

```rg
element_type : Type = type_of(.value = point)
bytes ::= size_of(.type = Point)
alignment ::= alignment_of(.type = Point)
```

Type queries do not execute an expression for its runtime effects. See
[Compile-time computation](50_comptime.md) for open questions about
compile-time introspection.

## Literal typing

Floating-point literals take the width of an explicit destination or function
parameter, including fields and array elements. Without that context they
default to `Float32`. This does not permit implicit conversions between typed
floating-point values.

## Conversion

Conversions are explicit. A call cannot select an overload solely from its
desired output type: [multiple dispatch](131_multiple_dispatch.md) uses the
function name and input types. Arithmetic does not silently convert values
between unrelated types.

Conversion uses the destination type as the callee. For example,
`UIntNative(.value = reference)` observes a reference's numeric address.
`UIntNative` is the pointer-sized integer type used for addresses. The
integer carries no validity dependency on the referenced storage.

Creating a reference from an address requires a named core operation that
connects it to a valid lifetime, such as `trusted_establish_inherited_reference`.
Allocation establishment creates a fresh root for newly acquired storage.
A type conversion alone cannot establish a live reference.

> [!QUESTION]
> Should an integer literal take a floating-point destination type in an
> assignment such as `x = 1` when `x` is `Float32`? This would be contextual
> literal typing, not an implicit conversion of an integer variable.

> [!QUESTION]
> How should user-defined conversions distinguish construction from
> representation conversion? Define how fallible conversions compose with
> constructors and how their overloads are selected.

## Type aliases

> [!QUESTION]
> Should `Name : Type = ExistingType` create an alias with the same type
> identity, or should distinct named wrappers be required? Define how an
> alias participates in dispatch and whether it converts implicitly to its
> underlying type. The spelling alone should not decide those rules.

> [!IDEA]
> An explicit underlying-type constraint, similar to Go's `~T`, could
> describe types with a common representation while preserving their distinct
> identities. It would need a separate rule from ordinary type aliases.
