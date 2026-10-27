# Structs

A struct definition literal creates a nominal type with named fields:

```rg
Coordinates := (
    .x: Int32
    .y: Int32 = 0
)

coordinates :: Coordinates = (.x = 20)
```

`coordinates.y` receives its declared default. Fields without defaults must be
initialized before the value is used. Field access uses `value.field`; the
same notation selects a field through a reference after dereferencing it.

Independent struct definitions are distinct even when their fields match.
Assigning a type value to another name preserves its identity. An unnamed
struct definition can also be written directly in an annotation:

```rg
position : (
    .x: Int32
    .y: Int32
) = (
    .x = 20
    .y = 22
)
```

That unnamed definition has its own identity. Value literals such as
`(.x = 20, .y = 22)` use the expected type and do not create another type.
An aggregate literal needs an annotation or explicit constructor when its type
cannot otherwise be determined. Constructors may accept positional arguments
when their order is unambiguous.

A constant struct binding cannot be reassigned, have its fields changed, or
be borrowed through `$&`. Reading its fields and taking `&` references
remain possible.

## Field visibility

A field whose name begins with `_` is private to the module that declares
the struct. Files in that directory share the module and may access it;
another module in the same distribution may not.

```rg
Counter := (
    ._value: Int32
)

read := (.counter: &Counter) -> (.value: Int32)  {
    value = counter&._value
}
```

Private fields let a module expose operations while controlling how values
are constructed and changed outside that module.

## Construction

A type can provide construction through the standard Init contract:

```rg
Point := (
    .x: Int32
    .y: Int32
)

PointArgs := (.x: Int32, .y: Int32)

implement Init#(Point, PointArgs) (
    .Result: Type = Point
    .init = (.args: PointArgs) -> (.result: Result) {
        result = (.x = args.x, .y = args.y)
    }
)

point := Point(.x = 20, .y = 22)
```

`Point(...)` selects Init evidence using Point and its argument record. The
associated Result must be Point or `Errable#(Point, R)` when construction can
fail. Result never selects the implementation. When Init applies, callers
cannot bypass its requirements through automatic field-wise construction. See
[Initialization and deinitialization](30_initialization_and_deinitialization.md)
for generic constructors and cleanup on failure.

## Structs and behavior

Argi has no object-owned methods or implicit receiver. A struct holds state;
ordinary functions operate on it through explicit inputs. For example:

```rg
move_x := (.point: $&Point, .delta: Int32) -> ()  {
    point&.x = point&.x + delta
}

{
    point :: Point = Point(20, 22)
    point | move_x($&_, 3)
}
```

## Layout

`size_of(.type = T)` and `alignment_of(.type = T)` return `UIntNative`
values. Ordinary struct layout is chosen by the compiler; code must not
assume field offsets from declaration order. C interoperation provides
`CStruct`, with the target's C field layout, and `CUnion`, whose fields share
storage. See [C interoperability](20_c.md).

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
> as a layout-based spelling of `CStruct`, and a more advanced `..Custom` with explicit offsets and
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
