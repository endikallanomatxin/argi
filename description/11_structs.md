# Structs

A named struct declares a distinct type with named fields:

```rg
Coordinates : Type = (
    .x: Int32
    .y: Int32 = 0
)

coordinates :: Coordinates = (.x = 20)
```

`coordinates.y` receives its declared default. Fields without defaults must be
initialized before the value is used. Field access uses `value.field`; the
same notation selects a field through a reference after dereferencing it.

Named types are nominal: two separately declared structs do not become the
same type merely because their fields match. An unnamed struct type can be
written directly in a declaration:

```rg
position : (
    .x: Int32
    .y: Int32
) = (
    .x = 20
    .y = 22
)
```

Unnamed struct types use their field structure for type identity. Struct
value literals provide fields by name; constructors may also accept
positional arguments when their order is unambiguous.

A constant struct binding cannot be reassigned, have its fields changed, or
be borrowed through `$&`. Reading its fields and taking `&` references
remain possible.

## Field visibility

A field whose name begins with `_` is private to the module that declares
the struct. Files in that directory share the module and may access it;
another module in the same package may not.

```rg
Counter : Type = (
    ._value: Int32
)

read(.counter: &Counter) -> (.value: Int32) := {
    value = counter&._value
}
```

Private fields let a module expose operations while controlling how values
are constructed and changed outside that module.

## Construction

A type may define `init` with a mutable destination and explicit inputs:

```rg
Point : Type = (
    .x: Int32
    .y: Int32
)

init(.p: $&Point, .x: Int32, .y: Int32) -> () := {
    p& = (.x = x, .y = y)
}

point := Point(.x = 20, .y = 22)
```

`Point(...)` selects a visible initializer for `Point`; the destination type
is already known from the constructor name. Selection is based on the input
types, not on a function's output type. An initializer must leave a complete
value on success. When a visible `init` exists, callers construct through
that operation rather than bypassing it with a field initializer.

An initializer that can fail returns one `Errable#(.t: Void, .reasons: R)`.
Then `Point(...)` returns `Errable#(.t: Point, .reasons: R)`, and `..ok`
contains the constructed point. The initializer must leave its destination
complete on success and empty on error.

## Layout

`size_of(.type = T)` and `alignment_of(.type = T)` return `UIntNative`
values. Ordinary struct layout is chosen by the compiler; code must not
assume field offsets from declaration order. C interoperation also provides
`CUnion`, whose fields share storage.

> [!IDEA]
> **Explicit struct layout.** A declaration could choose its layout while the
> ordinary default remains compiler-selected. For example, this is proposed
> syntax, not an available constructor:
>
> ```rg
> Packet : Type = struct(.layout = ..C)(
>     .tag: UInt8
>     .length: UInt32
> )
> ```
>
> Possible layout choices include `..Optimal` for compiler-selected padding,
> `..RespectOrder` for declaration order, `..Packed`, `..Aligned(n)`, `..C`
> for C ABI layout, and a more advanced `..Custom` with explicit offsets and
> size. The exact syntax and guarantees still need design. An `offset_of`
> query and an editor view of field offsets would make the chosen layout
> inspectable alongside `size_of` and `alignment_of`.

> [!IDEA]
> **Field-specific types.** A field such as `User.ID` could also name a distinct
> type with the representation of `Int64`. Code handling a collection of user
> identifiers could then accept `User.ID` values without passing whole `User`
> structs or treating arbitrary integers as identifiers. For example, a
> proposed declaration could use `ids: List#(.t: User.ID)`. Whether the field
> declaration itself creates that type, and which conversions it permits,
> remain open.

> [!IDEA]
> **Structural delegation.** A wrapper could explicitly expose selected
> operations of one field, for example `expose .buffer`, instead of writing
> forwarding functions for every operation. This would need rules for name
> conflicts and for which operations become visible.

> [!IDEA]
> Dot access could extend to structural indices, such as `array.3`, alongside
> `value.field`. Dynamic collections could still use their explicit `get` and
> `set` operations. The boundary between field access and indexing needs a
> separate design.
