# Memory

## Pointers

Para obtener la referencia a una variable (como en c, go, rust...):

```
p = &x
```

Para desreferenciar un puntero:

```
x = @p

-- o

&x = p

-- Que es syntactic sugar para lo anterior y se usa al pasar argumentos a funciones.
```

Su tipo es:

```
p: &int  -- que en realidad es algo como pointer<int>
```

No puede ser nulo. si se quiere hacer nulo, usar un nullable: `?&int`.

No se puede hacer aritmética con punteros.
Si quieres hacerlo, tienes que convertirlo en un tipo numérico, hacer la aritmética y luego volverlo a convertir en un puntero. Es suficientemente incómodo como para no hacerlo sin querer, te obliga a ser explícito para cagarla.
(from zig)

## Memory management

### HeapAllocation

Similar to zig,  and they are are used to allocate and deallocate memory.

```
Allocator : Abstract = [
	allocate(_, size: Int) : HeapAllocation
	deallocate(_, ha: HeapAllocation)
]
```

Allocators return a `HeapAllocation` struct, instead of a single pointer. This allows us to keep track of the size and the allocator used for the allocation, which is necessary for deallocateing the memory later.

```
HeapAllocation : Type = struct [
	.data : &Byte
	.size : Int  -- In bytes
	.allocator : Allocator
]
```

When initializing types, allocators are passed as arguments,
For ergonomy, most init functions will have a default allocator, and the user can override it if needed.

```
init(#t                   == HeapBuffer,
     size     : Int,
     allocator: Allocator =  std.PageAllocator
) := HeapBuffer {
	.data = allocator|allocate(size)
	.size = size
	.allocator = allocator
}
```

In a type:

```
Hashmap(from: type, to: type) : type = struct [
	allocator : Allocator
	data      : HeapAllocation
]


init(
	hm: Hasmap,
	allocator: Allocator = std.RTAllocator
) :=  {
	hm.allocator = allocator
	hm.data = allocator|allocate(...)
}


deinit := (hm: Hashmap) {
	hm.allocator|deallocate(hm.data)
}
```

So:

```
my_map := ["a"=1, "b"=2]
```

Will expand to:

```
my_map = Hashmap<String, Int>|init
my_map["a"] = 1
my_map["b"] = 2
```

And when calling init without an allocator, it will use the default one, which hides the complexity of memory management.


### Variable deinitialization and keep keyword

Para que la gestión de la memoria en el heap sea consistente con la del stack, siempre se liberará la memoria al salir del scope.

La palabra que usamos para referirnos a esto es `deinit` (que será lo contrario de `init`, `allocate / deallocate` y `init / deinit`).

```
{
	buf := HeapAllocation|init(_, 1024)
	-- El compilador siempre pone automáticamente:
	defer buf|deinit
}
```

Tipos que contengan memoria alocada en el heap implementarán deinit.

```
deinit(buf: HeapAllocation) {
	buf.allocator|deallocate(buf.data)
}
```

Y habrá también una por defecto para cualquier struct que llama de forma recursiva a deinit en sus campos.

```
deinit(s: AnyStruct) {
	-- Pensar en como hacer introspección. Qué tipo es un struct?
	for field in my_struct|#get_fields {
		field|deinit
	}
}
```

Para evitar que la memoria se autolibere, se puede usar el keyword `keep`:

```
{
	buf := HeapAllocation|init(_, 1024)
	keep buf
}
```

Si se hace kep sobre una variable en el stack, automáticamente la pasa al heap. Esto permite trabajar de forma coherente con el stack y el heap, y no tener que preocuparse de donde se encuentra la variable.

Una vez hecho `keep` sobre una variable, el usuario es el responsable de liberar la memoria.


#### Keep with a variable

Lo habitual es que no quieras tener que estar pendiente de hacerlo y que su vida esté ligada a la de otra variable. Para esos casos, y lo que será lo más habitual, se puede hacer:

```
{
	MyType : Type = struct [
		.field : &Int
	]
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

#### Resumen del sistema

Con esto se consigue un sistema de la gestión de la memoria que, aunque manual, es extremadamente cómodo de usar.

Seguramente los novatos no se encuentren con que tengan que hacer `keep` durante mucho tiempo, y cuando lo hagan será porque necesitan su comlejidad y será coherente con el resto del lenguaje.

> Safety total?
> No, pero en realidad ningún lenguaje lo es. Este me parece un buen compromiso entre seguridad y ergonomía.


### In-expression variable creation

En go (y en general en casi todos), el resultado de una llamada a función no es una variable "addressable" (con dirección en memoria), por lo que no puedes tomar su dirección directamente con la sintaxis `&(función(...))`. debes asignar el resultado a una variable y luego tomar su dirección, como se mostró anteriormente. esto es parte de las reglas del lenguaje.

El problema con esto es que nos rompe el workflow de piping, ya que no puedes hacer algo como:

```
myData
 | step1
 | step2
 | step3(&_)
 | step4
```

Eso es un problema.

Nuestro compilador debe ser capaz de inicializar variables intermedias a las que referirse, y que se limpien automáticamente al salir del scope.

> [!BUG] Pero entonces como se compagina eso con el `keep`? Deben permanecer accesibles o liberarse?
> Igual que se pueda pipear el keep? (Así sería algo como meterlo en una box)
> Una función que sea inline_keep() que cree la variable y la mantenga y de alguna manera asocie su lifetime a lo que devuelva.
> 
> Propuesta de chatgpt:
> Dos opciones:
> A) La memoria se mantiene viva solo para que la función lea algo de ella. En esta caso la variable se libera al salir del scope.
> B) La memoria se mantiene viva porque permanece en algo que la siguiente función devuelve. Para esto debe hacerse un box/keep explícito.
>
> Una idea:
>
> ```
> image :=
>     load_png("image.png") -- → DynamicArray<RGBA>
>     | keep _ with image  -- la imagen vive hasta vaciar el stack
>     | una_funcion_que_toma_los_pixels_y_devuelve_un_objeto_que_los_referencia(&_)
> ```
>
> Pensar mejores ejemplos.
> Pensar en como se compagina esto con threads.

Ejemplos:

Función que simplemente lee:

> ```
> tree := parse_expr("(+ 1 (* 2 3))")
>     | build_ast(&_)
> ```

Caso de builder pattern:

> ```
> body := SketchBuilder|init()
>     | trapezoid(&_, 4, 3, 90)
>     | fillet(&_, 0.25)
>     | extrude(&_, 0.1)
>```

Función que necesita referencia para paralelizar:

> ```
> result := load_png("image.png")
>     | keep _ with result
>     | parallel_process_that_only_reads(&_)
>     | parallel_process_that_writes(~&_)
> ```

> Si no pones nada, son variables que se eliminan al acabar el pipe.

> [!BUG] Y como sabes si la función necesita crear referencias y keepearlas?
> Igual esto requiere un tipo adicional de puntero?

> [!BUG] Las variables creadas son variables o constantes?
> Igual si la referencia creada es $& entonces es variable y si es & entonces constante?




## Alignment

```
MyStruct : Type = [
	.a : u8
	.b : u32
	.c : u16
]|layout(..Default)
```

Donde `layout()` puede tener valores como:

- **`default`**: El compilador optimiza para el menor padding posible.
- **`explicit`**: Respeta el orden de los campos como están declarados.
- **`packed`**: Minimiza el tamaño eliminando padding (puede penalizar rendimiento). Útil para comunicación.
- **`aligned(n)`**: Alinea la estructura al límite especificado (`n` bytes).
- **`c`**: Sigue el layout estándar de C (compatibilidad ABI). Respeta el orden de declaración de los campos en las estructuras y aplica padding únicamente para cumplir los requisitos de alineación.
- `custom()`. Recibe un struct con una lista de offsets y un size.

Herramientas para inspeccionar layout:

```
inspect_layout(MyStruct)
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

Conversión de layouts:

```
efficient_access_struct = packed_struct|layout(default)
```
