# Basic built-in types

## Booleans

`Bool` has the literals `true` and `false`. `and`, `or`, and `not` express
boolean operations.

> [!IMPLEMENTATION]
> The current compiler supports `and` and `or` but not `not`.

## Numbers

The fixed-width numeric types are:

| Kind | Types |
| --- | --- |
| Signed integers | `Int8`, `Int16`, `Int32`, `Int64` |
| Unsigned integers | `UInt8`, `UInt16`, `UInt32`, `UInt64` |
| Floating point | `Float16`, `Float32`, `Float64` |

`UIntNative` is an unsigned integer with the width of a pointer.

Integer literals use `Int32` by default and floating-point literals use
`Float32` by default.

Core defines `Int`, `UInt`, and `Float` as abstract contracts for numeric
types.

Arithmetic and comparison do not silently convert between different numeric
types. See [Types](10_types.md) for explicit conversion.

A literal can take a compatible expected type within its numeric kind. Whether
an integer literal can take a floating-point type is an open question in
[Types](10_types.md).

Integer literals accept decimal, binary (`0b`), octal (`0o`), and hexadecimal
(`0x`) notation. Floating-point literals accept decimal and scientific
notation.

An integer literal must fit its contextual type. A positive literal may use
the full unsigned range, including `18446744073709551615` for `UInt64` and
64-bit `UIntNative`. The same magnitude does not fit `Int64`. The minimum
`Int64` value is written `-9223372036854775808`; negative literals do not fit
unsigned types. A literal with no contextual type must fit the default `Int32`.

> [!IMPLEMENTATION]
> Digit separators such as `1_000_000` are intended but are not accepted by
> the current tokenizer.

> [!IDEA]
> Explore `DynamicInt`, arbitrary-width integers, and wider fixed-width
> integers and floats. Their representation, arithmetic rules, and possible
> use as literal defaults are undecided.

## Characters

`Char` holds a character value.

String types and views are described in [Strings](162_strings.md).

## Void

`Void` denotes an empty result.

## Type

`Type` is the type of types used in compile-time expressions.

## Any

`Any` is available at low-level erased-storage boundaries; it does not make
arbitrary values interchangeable.
