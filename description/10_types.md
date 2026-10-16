# Types

Type names conventionally use `PascalCase`; value names use `snake_case`.
Types are checked during compilation. A named type has its own identity:
two independently declared types do not become interchangeable merely
because their fields match. Unnamed structural types may be compared by
their field structure. See [Structs](11_structs.md) and [Choice](12_choice.md).

Types are values that can be passed as compile-time parameters. For example,
`Array#(4, Int32)` selects an array type using a length and an
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

## Integer arithmetic

The standard scalar integer arithmetic contracts wrap results to the operand
width, for both signed and unsigned integers. This behavior is the same in native
and VM execution and does not depend on the build mode. It does not change the
semantics of explicit checked conversions or custom arithmetic contracts.

Integer division rounds towards zero. `%` returns the remainder with the sign
of the dividend. The signed minimum divided by -1 wraps to the signed minimum;
the corresponding remainder is zero. Integer division or remainder by zero
aborts instead of invoking undefined behavior.

## Conversion

Conversions are explicit. [Contract dispatch](131_multiple_dispatch.md) selects
from known participant types, including an explicitly requested destination. An
expected associated result cannot infer missing participants or rank implementations.
Arithmetic does not silently convert values between unrelated types.

Conversion selects `Convert#(Source, Target)` with an explicit destination. For example,
`reference | convert#(.to: UIntNative)(_)` observes a reference's numeric address.
`UIntNative` is the pointer-sized integer type used for addresses. The
integer carries no validity dependency on the referenced storage.

Integer conversions use `convert#(.to: Destination)(.value = source)`. Their return type
depends on the complete ranges of the two types, never on the particular
value or the expected result type. If the destination contains the source's
entire range, the conversion returns the destination type directly. Otherwise
it returns `Errable#(Destination, (..out_of_range))`, including
when the supplied value happens to fit. A checked conversion returns an error
outside the destination's range; it never wraps, saturates, or truncates a
value outside that range.

```rg
byte : UInt8 = 255
wide : Int16 = byte | convert#(.to: Int16)(_)
checked ::= wide | convert#(.to: Int8)(_)  -- The Int16 range requires Errable.
```

The same rules apply to signedness changes, `UIntNative`, and C integer aliases.
Native widths and aliases use the compilation target. All conversions between
typed integer values remain explicit, including widening conversions in
assignments, function arguments, arithmetic, and comparisons. Literals retain
their contextual typing rules; a conversion argument without a type context
uses the normal literal default.

Creating a reference from an address requires a named core operation that
connects it to a valid lifetime, such as `trusted_establish_inherited_reference`.
Allocation establishment creates a fresh root for newly acquired storage.
A type conversion alone cannot establish a live reference.

> [!QUESTION]
> Should an integer literal take a floating-point destination type in an
> assignment such as `x = 1` when `x` is `Float32`? This would be contextual
> literal typing, not an implicit conversion of an integer variable.

User-defined conversions implement `Convert#(Source, Target)`. Its `Result` must
be `Target` or an `Errable` containing it. Construction uses `Init` separately;
conversion never selects an implementation from the expected result type.

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
