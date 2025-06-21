# Memory

## Pointers

Para obtener la referencia a una variable (como en c, go, rust...):

```
p = &x
```

Para desreferenciar un puntero:

```
x = p&
```

Su tipo es:

```
p: &Int
```

No puede ser nulo. (Si se quiere hacer nulo, usar un nullable: `?&int`. Más adelante hay más sobre esto.)


No se puede hacer aritmética con punteros.
Si quieres hacerlo, tienes que convertirlo en un tipo numérico, hacer la aritmética y luego volverlo a convertir en un puntero. Es suficientemente incómodo como para no hacerlo sin querer, te obliga a ser explícito para cagarla.
(from zig)


## Memory management

### HeapAllocation

Similar to zig,  and they are are used to allocate and deallocate memory.

```
Allocator : Abstract = (
	alloc (_, size: Int) -> HeapAllocation
	dealloc (_, ha: HeapAllocation) -> ()
)
```

Allocators return a `HeapAllocation` struct, instead of a single pointer. This allows us to keep track of the size and the allocator used for the allocation, which is necessary for deallocateing the memory later.

```
HeapAllocation : Type = (
	.data : &Byte
	.size : Int  -- In bytes
	.allocator : Allocator
)
```

When initializing types, allocators are passed as arguments,
For ergonomy, most init functions will have a default allocator, and the user can override it if needed.

```
init (
    size     : Int,
    allocator: Allocator =  std.PageAllocator
) -> (.ha: HeapAllocation) := {
	ha = HeapAllocation (
		.data      = allocator|allocate(size)
		.size      = size
		.allocator = allocator
	)
}
```


In a type:

```
Hashmap <from: Type, to: Type> : Type = (
	.allocator : Allocator
	.data      : HeapAllocation
)


init(.allocator: Allocator = std.RTAllocato) -> (.hm: HashMap<from, to>) :=  {
	hm : Hashmap <from, to>
	hm.allocator = allocator
	hm.data = allocator|allocate(...)
}


deinit (.hm:$&Hashmap&) -> () := {
	hm.allocator|deallocate(hm.data)
}
```

> [!FIX] Pensar en la sintaxis apropiada para generics.
> from y to serían argumentos de entrada? Hay que definirlos al crear el tipo? Asumo que sí.
> El output hay que inicializarlo? O viene inicializado por defecto?
> Como se especifica la mutabilidad si solo hay un tipo? Igual deberíamos obligar a que siempre fuera un struct.

So:

```
my_map := ("a"=1, "b"=2)
```

Will expand to:

```
my_map : hashmap<string, int> = init (.content = ("a"=1, "b"=2), .allocator = std.rtallocator)
```

> [!FIX] Pensar en la sintaxis apropiada para crear un hashmap.

And when calling init without an allocator, it will use the default one, which hides the complexity of memory management.


### Variable deinitialization and keep keyword

Para que la gestión de la memoria en el heap sea consistente con la del stack, siempre se liberará la memoria al salir del scope.

La palabra que usamos para referirnos a esto es `deinit` (que será lo contrario de `init`, `allocate / deallocate` y `init / deinit`).

```
{
	buf : HeapAllocation = init 1024
	-- El compilador siempre pone automáticamente:
	defer buf | deinit
}
```

Tipos que contengan memoria alocada en el heap implementarán deinit.

```
deinit HeapAllocation {
	in.allocator | deallocate (_, in.data)
}
```

Y habrá también una por defecto para cualquier struct que llama de forma recursiva a deinit en sus campos.

```
deinit AnyStruct -> () := {
	-- Pensar en como hacer introspección. Qué tipo es un struct?
	for field in in | #get_fields {
		field|deinit
	}
}
```

Para evitar que la memoria se autolibere, se puede usar el keyword `keep`:

```
{
	buf : HeapAllocation = 1024
	keep buf
}
```

Si se hace kep sobre una variable en el stack, automáticamente la pasa al heap. Esto permite trabajar de forma coherente con el stack y el heap, y no tener que preocuparse de donde se encuentra la variable.

Una vez hecho `keep` sobre una variable, el usuario es el responsable de liberar la memoria.


#### Keep with a variable

Lo habitual es que no quieras tener que estar pendiente de hacerlo y que su vida esté ligada a la de otra variable. Para esos casos, y lo que será lo más habitual, se puede hacer:

```
{
	MyType : Type = (
		.field : &Int
	)
	my_instance : MyType

	my_int := 5
	my_instance.field = &my_int
	keep my_int with my_instance

	return my_instance  -- Se puede devolver la variable, porque no se ha liberado
}
```

Esto pospone la liberación de la memoria hasta justo antes de que se de la liberación de su variable padre.

Si devuelves un puntero o cualquier variable que lo contenga y no has hecho `keep` el compilador dará un error.

> Esto es algo parecido a rust pero sin el borrow checker, lo tienes que indicar tú.


#### Keep with multiple variables

Una variable puede ligar su vida a varias variables. En ese caso, se liberará cuando todas las variables que la referencian se liberen.

```
{
	my_instance1 : MyType
	my_instance2 : MyType
	
	my_int := 5

	my_instance1.field = &my_int
	my_instance2.field = &my_int
	keep my_int with my_instance1, my_instance2
}
```

> Aquí es donde divergimos de Rust, que solo permite un single owner.

En este caso, se creará un contador de referencias y se liberará cuando el contador llegue a 0.

Es algo parecido a Swift, pero con la diferencia de que en Swift todos los objetos tienen un ARC, independientemente de que su vida no se extienda más allá de un scope y la gestión de la memoria sea trivial.

Ahora bien, el gran punto débil de ARC son los ciclos.
El compilador no es capaz de detectar todos los casos. De todas formas, los que sí pueda detectar darán error de compilación y se le aconsejará al usuario que ligue la lifetime de las variables a una variable central o que use un arena allocator.


#### Interaction with function calls

Keeping is usually done inside the function that creates de dependant variable. This is where it is more obvious the relationship between the two variables and it makes for a cleaner interface (lifetime encapsulation).

This is critical for the ergonomics of piping, where keeping needs to be done automatically.

For this to work correctly when keep the thing pointed by the input of the function, the compiler needs to be able to infer that you are keeping the original variable.

Si un parámetro por referencia aparece en la salida o se guarda en un campo global, el analizador comprueba que existe un keep correlativo y si no, da error.


#### Resumen del sistema

Con esto se consigue un sistema de la gestión de la memoria que, aunque manual, es extremadamente cómodo de usar.

Seguramente los novatos no se encuentren con que tengan que hacer `keep` durante mucho tiempo, y cuando lo hagan será porque necesitan su comlejidad y será coherente con el resto del lenguaje.

> Safety total?
> No, pero en realidad ningún lenguaje lo es. Este me parece un buen compromiso entre seguridad y ergonomía.


### In-expression variable creation

En la mayoría de lenguajes, si anidas llamadas de funciones, no puedes pasarle a una como input una referencia al output de otra. Como esas variables intermedias no existe, no pueden crearse referencias.
Pero esto le quita mucha ergonomía al lenguaje, sobre todo al piping de funciones.

En nuestro lenguaje, cuando hay funciones anidadas o pipeadas:

- Las variables intermedias se crean automáticamente.
- Si la función que las usa necesita una referencia &, entonces son constantes, si necesita una $&, entonces son variables.
- Si no se hace keep de las variables dentro de la siguiente función, se desinicializan tras esa siguiente función.


Ejemplos:

Caso de builder pattern:

```
body :=
      SketchBuilder|init()
    | trapezoid(&_, 4, 3, 90)
    | fillet(&_, 0.25)
    | extrude(&_, 0.1)
```

Función que necesita referencia para paralelizar:

```
result :=
      load_png("image.png")
    | keep _ with result
    | parallel_process_that_only_reads(&_)
    | parallel_process_that_writes(~&_)
```



## Struct memory layout

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


