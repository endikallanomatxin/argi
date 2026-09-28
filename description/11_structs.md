# Structs

This declares a new struct type:

```
Pokemon : Type = (
	.ID   : Int64  = 0    -- It allows default values
	.Name : String = ""
)
```


This declares a new anonymous struct:

```
data : (
	.ID   : Int64    -- Struct type literal
	.Name : String
) = (
	.ID = 0          -- Struct value literal
	.Name = ""
)
```

Structs' types are structural only when anonymous.

> [!IDEA] Default fields could be filled in the call site.
> This helps by reducing the need to dive into the function calls to see what
> inputs are being overridden.

## Protected fields

It is important to protect some fields to provide better encapsulation.

Fields starting with `_` will be private and cannot be accessed from
outside the package.

For example:

```
MyStruct : Type = (
	._x :: Int = 0
)

get_x(s: MyStruct) := Int {
	return s._x
}

set_x(s: MyStruct, x: Int) {
	s._x = x
}
```

This can also help ensure that a struct is initialized correctly.

```
MyStruct : Type = (
	._x :: Int = 0
	._y :: Int = 0
	._z :: Int = 0
)

init (ms: $&MyStruct, x: Int, y: Int, z: Int) -> () := {
	return MyStruct(x, y, z)
}
```

We use dynamic dispatch by return type to create the initializer.

```
my_var := MyType(1, 2, 3)
```

This is really:

```
my_var : MyType
init($&my_var, 1, 2, 3)
```

This keeps the syntax very clean.


> [!IDEA] Struct field types
> For example, in a Go web app, model structs can have many fields that are not
> always used in full.
> Sometimes you pass the whole struct even when you only need its ID field, just
> to preserve the semantics.
> Perhaps defining a struct could also define new types.
> 
> For example:
>
>	```
>	User := (
>		ID    :: Int64
>		Name  :: String
>	)
>	userIDs : List(User.ID)  -- Instead of Users, or simply Int64.
>	```
>
> This gives us semantic information about what we are using without the cost
> of passing the entire struct.


> [!IDEA] Structural delegation with `expose`
> A struct could explicitly expose operations of one of its fields, for example
> `expose .buffer`, to remove forwarding boilerplate in wrapper types.

## Memory layout

You can specify:
- **alignment**: How the struct is aligned in memory.
- **listing_behavior**: How the fields are listed in memory (AOS or SOA).


```
MyStruct : Type = struct(
    alignment: ..RespectOrder
    listing_behavior: ..SOA
)(
	.a : u8
	.b : u32
	.c : u16
)
```

AOS and SOA, are inspected when creating lists (taken care of in the core library).

```
StructListingBehaviour : Type = (
    =..AOS
    -- Array of Structures (AOS) layout.
    -- Each element is a structure, and fields are stored together.

    ..SOA
    -- Structure of Arrays (SOA) layout.
    -- Each field is stored in a separate array, optimizing memory access patterns.
)
```

Struct layout is something that the compiler takes care of.

```rg
StructLayout : Type = (
    =..Optimal
    -- Compiler optimizes for minimal padding.

    ..RespectOrder
    -- Respects the order of fields as declared.

    ..Packed
    -- Minimizes size by removing padding (may penalize performance). Useful for communication.

    ..Aligned(n)
    -- Aligns the struct to the specified boundary (n bytes).

    ..Custom(offsets: List(Int), size: Int)
    -- Custom layout with specified offsets and size.

    ..C
    -- Follows the C standard layout (ABI compatibility). Respects the order of
    -- field declaration in structures and applies padding only to meet alignment
    -- requirements.
)
```

Tools for inspecting layout:

```
inspect_layout MyStruct
```

```
Layout of MyStruct:
Field    Offset    Size    Alignment
a        0         1       1
b        4         4       4
c        8         2       2
Total size: 12 bytes (4 bytes of padding)
```
perhaps even a small diagram
```
A...BBBBCC..
```
that could appear below the declaration in the editor.


The language should provide standard functions for querying layout at runtime:
- **`align_of`**: Returns the alignment of a type.
- **`size_of`**: Returns the size of a type.
- **`offset_of`**: Returns the offset of a field in a struct.

`size_of` and `align_of` should return `UIntNative`.
