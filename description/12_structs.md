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


## Protected fields

Es importante proteger algunos campos para conseguir una mejor encapsulación.

Los campos que empiecen por _ serán privados y no podrán ser accedidos desde
fuera del package.

Por ejemplo:

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

También puede ser útil para garantizar que un struct se inicializa correctamente.

```
MyStruct := (
	._x :: Int = 0
	._y :: Int = 0
	._z :: Int = 0
)

init (x: Int, y: Int, z: Int) -> MyStruct := {
	return MyStruct(x, y, z)
}
```

We use dynamic dispatch by return type to create the initializer.

```
my_var : MyType = (1, 2, 3)
```

Esto realmente es:

```
my_var : MyType = init (1, 2, 3)
```

y queda muy limpio.


> [!IDEA] Struct field types
> Cuando tienes una app web en go por ejemplo, tienes structs para tus models que tienen un montón de campos que más adelante no vas a usar siempre al completo.
> A veces aunque solo tengas que usar el campo del ID pasas el struct entero para al menos mantener la semántica.
> Igual se podría hacer que cuando se define un struct también se definen tipos nuevos.
> 
> Por ejemplo:
>
>	```
>	User := (
>		ID    :: Int64
>		Name  :: String
>	)
>	userIDs : List(User.ID)  -- En lugar de Users, o simplemente Int64
>	```
>
> Con esto ganamos la información semántica de a qué corresponde lo que estamos usando, sin pagar el precio de pasar todo el struct.


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

Herramientas para inspeccionar layout:

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
igual incluso un dibujito
```
A...BBBBCC..
```
que se podría poner debajo de la declaración en el editor.


El lenguaje debe proporcionar funciones estándar para interactuar con el layout en tiempo de ejecución:
- **`align_of`**: Devuelve la alineación de un tipo.
- **`size_of`**: Devuelve el tamaño de un tipo.
- **`offset_of`**: Devuelve el offset de un campo en una estructura.


