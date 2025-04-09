## Memory

#### Pointers

Es un tipo:
```
p: Ptr<Int>
```

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

Apunta a un solo elemento y no puede ser nulo (para hacerlo nulo, usar un option).

```
-- Si puede ser null
Option(Pointer(Int))
```

En zig también hay tipos de puntero:
- Pointer to just one element
- Pointer to unknown length segment of memory
- Pointer with length.
Esto ayuda a aclarar muchas dudas que se dan en c.
Pensar en si merece la pena implementarlo y como hacerlo.

```
-- For arrays, strings...
LengthedPointer<#T: Type> := struct [
	pointer : Pointer(T)
	length  : Int
]


-- Mainly for C interop
UnknownLengthedPointer<T: Type> : struct = [
	pointer : Pointer(T)
]

AnyPointer<#T: Type> : abstract = [
	...
]

AnyPointer<T> canbe [
	Pointer<T>
	LengthedPointer<T>
	UnknownLengthedPointer<T>
]

AnyPointer defaultsto Pointer(T)
```

No se puede hacer aritmética con punteros.
Si quieres hacerlo, tienes que convertirlo en un tipo numérico, hacer la aritmética y luego volverlo a convertir en un puntero. Es suficientemente incómodo como para no hacerlo sin querer, te obliga a ser explícito para cagarla.
(From zig)

En Go, el resultado de una llamada a función no es una variable "addressable" (con dirección en memoria), por lo que no puedes tomar su dirección directamente con la sintaxis `&(función(...))`. Debes asignar el resultado a una variable y luego tomar su dirección, como se mostró anteriormente. Esto es parte de las reglas del lenguaje.
Eso no me gusta. Deberías poder hacer a = &(function(...))
Aunque igual tiene sentido que no se pueda, claro; si no has definido ni la variable, como vas a tener un putero a esa variable.
No se igual simplemente que el compilador auto genere una variable igual es suficiente y lo hace más cómodo.


### Memory management

_Es importante encontrar un sistema que permita el control manual para los expertos, pero que por defecto tenga una gestión automática._

Similar to zig, allocators are passed as arguments, and they are are used to allocate and free memory.

Sin embargo, often the user doesn't have to worry about it. Most heap allocated memory is automatically managed by default allocators. 


```
HashMap(from: Type, to: Type) : Type = struct [
	allocator : Allocator
	data      : Option(Pointer)
]


init(
	hm: Hasmap,
	allocator: Allocator = std.RTAllocator
) :=  {
	hm.allocator = allocator
	hm.data = allocator|allocate(...)
}


deinit := (hm: Hashmap) {
	hm.allocator|free(hm.data)
}
```

```
my_map := ["a"=1, "b"=2]
```

Will expand to:

```
my_map = Hashmap<String, Int>|init
my_map["a"] = 1
my_map["b"] = 2
```

And when calling init withou an allocator, it will use the default one, which hides the complexity of memory management.


##### Reference tracking allocator

Necesita que se "notifiquen" algunos eventos

- La creación de referencias.
- Duplicación de referencias.
- La eliminación de referencias.
- La salida de scope.

Además, si distintos "objetos" se referencian entre sí, los allocators tienen que combinarse para poder identificar ciclos.

Lo bueno es que como tipos no relacionados tienen allocators diferentes, no se tiene que comprobar la conectividad, hay que tener en cuenta menos referencias y es más eficiente.

Para implementar la funcionalidad necesitamos crear referencias sin avisar que se crean, para eso usamos un símbolo para indicar que no se llame a las notificaciones. `$`, de silent, por ejemplo.


Hay que registrar las referencias cuando se hace &objeto o cuando se usa el puntero.

```
RTAllocatedType : Abstract = [
	allocator : Allocator
]


init(
	obj       : RTAllocatedType,
	allocator : Allocator = std.RTAllocator
) :=  {
	obj.allocator = allocator
	obj.data = allocator|allocate(...)
}


deinit := (obj: RTAllocatedType) {
	obj.allocator|free(obj.data)
}
```

```
create_reference(obj: RTAllocatedType) := Pointer<RTAllocatedType> {
	p = $&obj  -- Silent reference
	if obj.allocator is RTAllocator {
		obj.allocator|register_reference(&p)
	}
	return p
}
```

```
copy(p: Pointer<RTAllocatedType>) := Pointer<RTAllocatedType> {
	new_p = $p  -- Silent copy
	if obj.allocator is RTAllocator {
		obj.allocator|register_reference(&new_p)  -- Cuando se crea es directamente accesible.
	}
	return new_p
}
```

```
exit_scope(obj: RTAllocatedType) {
	if obj.allocator is RTAllocator {
		obj.allocator|exit_scope(&obj)
	}
}

exit_scope(p: Pointer<RTAllocatedType>) {
	obj = @p
	if obj.allocator is RTAllocator {
		obj.allocator|exit_scope(&p)
	}
}
```


Para los punteros a este tipo de dato:

```
deinit(p: Pointer<RTAllocatedType>) := {
	obj = @p
	if obj.data != null {
		obj.allocator|mark_unaccessible(p)
		obj.allocator|free
	}
	obj.data = null
}
```

**Allocator**

```
RTAllocator : Type = struct [
	tracked_allocations : Hashmap(AllocationReference->HashSet(Reference))
	-- Allows for combination of allocators
]

AllocationReference : Type = struct [
	-- Points directly to the location on the heap that has been allocated
	-- Created at initialization
	pointer                : HeapPrt
	is_directly_accessible : Bool
]

Reference : Type = struct [
	-- This is a pointer to anything containing a reference to the allocation
	pointer                : Ptr<Any>
	is_directly_accessible : Bool
]
```

```
allocate(a: RTAllocator) := Pointer {
	p = a|allocate
	a|track_allocation(p)
	return p
}

free(a: RTAllocator, p: Ptr) {
	a|free(p)
}
```

```
track_allocation(a: RTAllocator, p: Ptr) := {
	-- For new allocations, only called once
	ar = AllocationReference(p, true)
	hs = HashSet().init(page_allocator)
	a.tracked_allocations[ar] = hs
}

combine(a1: RTAllocator, a2: RTAllocator) := (c: RTAllocator) {
	-- Should I initialize c? Automatic initialization cannot have a custom allocator...
	for ap, hs in a1.tracked_allocations {
		c.tracked_allocations[ap] = hs
	}
	for ap, hs in a2.tracked_allocations {
		if ap in tracked_allocations {
			c.tracked_allocations[ap]|combine(!&_, hs)
		} else {
			c.tracked_allocations[ap] = hs
		}
	}
	return c
}

register_reference(a: RTAllocator, ap: HeapPtr, p: Ptr) := {
	ar = AllocationReference(ap, true)  -- Esto no es correcto, porque va a sobreescribir con true
	r = Reference(p, true)
	a.tracked_allocations[ar]|append(r)
}


mark_not_directly_accessible(a: RTAllocator, ap: HeapPtr, p: Ptr) := {
	ar = AllocationReference(ap, true)  -- Esto no es correcto, porque va a sobreescribir con true
	r = Reference(p, true)
	a.tracked_allocations[ar][r].is_directly_accesible = false

	-- CHECK 1
	-- Hay que checkear a ver si esto hace que la variable ya no sea accesible,
	-- (ni directa ni indirectamente)

	Encontrar las referencias que apuntan a p
	For referencia in referencias
		Subir aguas arriba, a ver si hay alguna directamente accesible
		(detectando ciclos)
		Si sí,
			-- entonces solo hay que marcar p como no_directamente_accesible
			-- pero no hay que liberar nada
			continue
		Si no,
			-- significa que esta referencia hay que liberarla porque no es accesible
			-- (ni directa, ni indirectamente)
			a|remove_reference(ap, p)  -- Ahí ocurre el check 2
}


remove_reference(a: RTAllocator, ap: HeapPtr, p: Ptr) := {
	a.tracked_references[ap]|remove(p)

	if a.references|len == 0
		-- p was the last reference
		item = @ap  -- It gets the item referenced
		item|deinit

	-- CHECK 2
	-- Igual hay que liberar algunas de las que se mantenían con vida por esta

	references = encontrar_las_referencias_a_las_que_apuntaba_p
	for r in references
		Buscar qué otras referencias las referencian (aguas arriba)
		hasta encontrar alguna que sea directamente accesible.
		(Hay que poder detectar ciclos, para eso marcar las que se van visitando)

		If se encuentra una directamente accesible,
			entonces se mantiene
		Else,
			significa que esa referencia ya no es accesible (ni directa, ni indirectamente)
			Y por lo tanto se puede liberar.
```


**Implementarlo en un tipo propio**

Para que un tipo propio pueda ser gestionado por el RTAllocator, simplemente:

```
MyType : Type = struct [
	...
	allocator : RTAllocator
]

RTAllocatedType canbe MyType
```



**Concurrency**: Si quieres concurrencia, lo metes todo en un mutex. Lo ibas a tener que hacer igual y así nos ahorramos tener que hacer los allocators thread safe.

###### Removal

El compilador debería dar herramientas para que pudieras comprobar si todas las variables son owned y así quitarle trabajo al gc.

```
lang check-signal-use main.l
```

Si consigues que el uso sea cero, puedes quitarlo.

```bash
lang build main.l--no-signals
```

Si no se usa el gc o no hay otras referencias a estas funciones, entonces no se emiten esos eventos.


##### Box

Lo que hemos visto hace más cómodo trabajar con objetos que se almacenan en el heap.
Pero a veces hay datos que se almacenan en el stack y que queremos que vivan más allá del scope en el que se han creado.
Para eso, podemos usar un Box.

```
Box(T: Type) := struct [
	data : T
]
```

```plaintext
b := Box(Int)
b.data = 5
```

No estoy muy seguro de si merece la pena. Igual mejor que simplemente se haga a mano.

Igual esto?

```
variable|to_heap
variable|to_stack
variable|to_arena(arena)
```

Funcionaría?

O igual cuando hace return de algo que siempre recolecte las variables que estén relacionadas y si están en el stack, que las pase al stack del caller.

> [!IDEA]
> Que RTAllocator sea un abstract y que sea muy fácil implementar en tus propios tipos.
> Simplemente poner un campo .Allocator: Allocator, y decir RTAllocatedType canbe MyType


##### Arenas

Hacer malloc y free requiere system calls, por lo que es lento.

Una arena es básicamente alocar memoria por chunks (pages por ejemplo) para reducir el número de veces que se llama a malloc y free.

Se puede usar también como una especie de stack dinámico. Por scopes. Con eso se puede conseguir evitar el garbage collector.

Echarle un pensamiento, porque es bastante eficiente.


### Alignment

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
