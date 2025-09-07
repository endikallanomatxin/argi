# Memory management

## Allocators

Similar to zig, they are are used to allocate and deallocate memory.

```
Allocator : Abstract = (
	alloc (_, size: Int) -> HeapAllocation
	dealloc (_, ha: HeapAllocation) -> ()
)
```

Allocators más típicos en zig:
- **PageAllocator**
  - Allocates memory from the OS, using `mmap` or `VirtualAlloc`.
  - Used for general-purpose allocations at runtime.
- **ArenaAllocator**
  - Allocates memory in chunks from the heap.
  - Useful for compilers, parsers, and loaders that need to allocate a lot of
  memory at once.
- **FixedBufferAllocator**
  - Allocates memory from a fixed-size buffer, which can be on the stack.
  - Used for temporary allocations without heap overhead.
- **GeneralPurposeAllocator**
  - A general-purpose allocator with additional safety features like redzones
  and leak detection.
  - Used for debugging applications.
- **ThreadLocalAllocator**
  - A bump-pointer allocator per thread with a fallback mechanism.
  - Used in multi-threaded applications to avoid contention.
- **DirectAllocator**
  - Uses `malloc` and `free` from the C standard library.
  - Useful for integrating with C libraries.


Para crear un nuevo allocator, tiene que tomar la capability `memory` de
`system` y usarla para crear un nuevo allocator.

```
init (.memory: &System.Memory) -> (.allocator: PageAllocator) := { ... }
```


## HeapAllocation

Allocators return an `Allocation` struct, instead of a single pointer. This
allows us to keep track of the size and a pointer to the allocator used for the
allocation, which is necessary for deallocateing the memory later.

```
Allocation : Type = (
	.data      : &Byte
	.size      : Int  -- In bytes
	.allocator : &Allocator
)
```

When initializing types, allocators are passed as arguments,

```
init (
    size     : Int,
    allocator: Allocator
) -> (.ha: HeapAllocation) := {
	ha = HeapAllocation (
		.data      = allocator|allocate(size)
		.size      = size
		.allocator = allocator
	)
}
```

```
my_buf : HeapAllocation = init(1024, my_allocator)
```

As the allocator needs the memory capability, it is not possible to define a
default allocator. The user must provide one when initializing the type.

> [!BUG] Igual esto es muy limitante.


In a type:

```
Hashmap#(.from: Type, .to: Type) : Type = (
	.data      : Allocation
)


init (.allocator: Allocator, content: MapLiteral) -> (.hm: HashMap#(f, t)) :=  {
	hm : Hashmap#(f, t)
	hm.data = allocator|alloc(1024)
	...
}

-- When adding stuff check capacity and reallocate if necessary.

deinit (.hm:$&Hashmap&) -> () := {
	hm.data|dealloc(_)
}
```

```
my_map : HashMap#(String,Int32) = init (my_allocator, ("a"=1, "b"=2))
```

> [!FIX] Reflexionar sobre la sintaxis para incializar un mapa.
> Lo ideal sería:
> ```
> my_map := ("a"=1, "b"=2)
> ```
> El no tener un default allocator perjudica mucho la ergonomía del lenguaje.
> Pensar en hacer que no sea una capability


## Variable deinitialization and keep keyword

Para que la gestión de la memoria en el heap sea consistente con la del stack,
siempre se liberará la memoria al salir del scope. `deinit`.

```
my_obj : Obj = ...

-- El compilador siempre pone automáticamente
#defer my_obj|deinit(_)
```

Los structs que no implementen `deinit` se liberarán con la función para
structs general, que desinicializa los campos por separado.

```
deinit (.s: AnyStruct) -> () := {
	-- Pensar en como hacer introspección. Qué tipo es un struct?
	for field in s | #get_fields {
		field|deinit
	}
}
```

Para evitar que un objeto se autolibere, se puede usar el keyword `keep`:

```
my_obj : Obj = ...

my_ref = &my_obj
#keep my_obj with my_ref using my_allocator
```

Como se relaciona esto con:

- `HeapAllocation`
    - es un descriptor, entonces se autoliberará al salir del scope, por eso es
    mejor usar esto que usar directamente malloc/free.
    - si se mete el descriptor en algún sitio, se deep-copia la memoria. Así se
    evita que haya double free.
    - si haces un puntero al descriptor, entonces tendrás que hacer keep, para
    que no se libere. (Si haces varios punteros, entonces tendrás que keep con
    todos ellos.) En cualquiera de los casos, keep copia el descriptor al heap
    para que pueda pervivir.

    > [!BUG] En el uso habitual, siempre habrá que hacer un puntero indirecto innecesario
    >
    > Igual hacen falta move semantics para que por defecto sea shallow copy.
    > Y así evitar estas situaciones.
    >
    > Hay dos approaches que pueden funcionar:
    >     - Always deep-copy
    >     - Once-only shallow-copy. clone if needed more.

- Una referencia a una variable en el stack.
    - Si haces keep a esa variable tras el puntero, se copia al heap.


Una vez hecho `keep` sobre una variable, el usuario es el responsable de liberar la memoria.


### Keep with a variable

Lo habitual es que no quieras tener que estar pendiente de hacerlo y que su
vida esté ligada a la de otra variable. Para esos casos, y lo que será lo más
habitual, se puede hacer:

```
{
	MyType : Type = (
		.field : &Int
	)
	my_instance : MyType

	my_int := 5
	my_instance.field = &my_int
	#keep my_int with my_instance

	return my_instance
	-- Se puede devolver la variable, porque el field se ha copiado al heap.
}
```

Esto pospone la liberación de la memoria hasta justo antes de que se de la
liberación de su variable padre.

Si devuelves un puntero o cualquier variable que lo contenga y no has hecho
`keep` el compilador dará un error.

> Esto es algo parecido a rust pero sin el borrow checker, lo tienes que
> indicar tú.


### Keep with multiple variables

Una variable puede ligar su vida a varias variables. En ese caso, se liberará
cuando todas las variables que la referencian se liberen.

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

En este caso, se creará un contador de referencias y se liberará cuando el
contador llegue a 0.

Es algo parecido a Swift, pero con la diferencia de que en Swift todos los
objetos tienen un ARC, independientemente de que su vida no se extienda más
allá de un scope y la gestión de la memoria sea trivial.

Ahora bien, el gran punto débil de ARC son los ciclos. El compilador no es
capaz de detectar todos los casos. De todas formas, los que sí pueda detectar
darán error de compilación y se le aconsejará al usuario que ligue la lifetime
de las variables a una variable central o que use un arena allocator.


### Interaction with function calls

Keeping is usually done inside the function that creates de dependant variable.
This is where it is more obvious the relationship between the two variables and
it makes for a cleaner interface (lifetime encapsulation).

This is critical for the ergonomics of piping, where keeping needs to be done
automatically.

For this to work correctly when keep the thing pointed by the input of the
function, the compiler needs to be able to infer that you are keeping the
original variable.

Si un parámetro por referencia aparece en la salida o se guarda en un campo
global, el analizador comprueba que existe un keep correlativo y si no, da
error.


### Resumen del sistema

Con esto se consigue un sistema de la gestión de la memoria que, aunque manual,
es extremadamente cómodo de usar.

Seguramente los novatos no se encuentren con que tengan que hacer `keep`
durante mucho tiempo, y cuando lo hagan será porque necesitan su complejidad y
será coherente con el resto del lenguaje.

> Safety total?
> No, pero en realidad ningún lenguaje lo es.
> Este me parece un buen compromiso entre seguridad y ergonomía.



## In-expression variable creation

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


---

>[!idea] Garbage collector puede ser un allocator que toma Async.

---

> [!check] ginger bill dice: I don't want to define my lifetimes based on my value, I want to be based on control flow (this loop, this function)

