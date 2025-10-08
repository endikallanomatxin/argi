## Definition of ownership

For automatization of memory management,

- types that own data on the heap should have:

    - An init method to allocate and initialize the data.
    - A deinit method to free the data. (ASAP)

- data on the heap should only have a single owner at any given tyme,
responsible for calling deinit when the data is no longer needed.

> The fundamental rules that make Mojo's ownership model work are the
> following:
>     - Every value has only one owner at a time.
>     - When the lifetime of the owner ends, Mojo destroys the value.
>     - If there are existing references to a value, Mojo extends the lifetime
>       of the owner.


## Copying

There are two methods for copying values:

- deep_copy(). Copies all the referenced data.

    It is always safe.


- shallow_copy(). Copies the reference but not the referenced data.

    Is only safe once and if transfers the ownership.


To maintain consistency with the stack mental model,
deep_copy() has to be the default.

```
m1 : Map = ()
m2 = m1  -- Aquí se debe hacer deep copy
```

Algunos tipos (archivos, sockets, dispositivos de hardware, semáfores, GPU
buffers...) no tiene sentido definir una deep copy. En estos casos,
directamente no se puede pasar por valor, solo con un puntero. Así eres
extra-explícito. Gracias a que la copia requiera una implementación explícita,
da la oportunidad de gestionarlo adecuadamente.

## Kinds of types

- Owning types

    **Can only be shallow-copied once. Transfering ownership**
    Have an init and deinit method.
    Examples: DynamicString, DynamicArray...

- Referencing types (views...)

    Should not be copied without extending the lifetime of the referenced data.

> In mojo:
> - A variable owns its value. A struct owns its fields.
> - A reference allows you to access a value owned by another variable. A
>   reference can have either mutable access or immutable access to that value.
> 
> Mojo references are created when you call a function: function arguments can
> be passed as mutable or immutable references.



> [!BUG] Some types can be both
> (linked list nodes, graph nodes, several types that reference others and own some data)
> How should we handle that?


> Mojo doesn't enforce value semantics or reference semantics. It supports them
> both and allows each type to define how it is created, copied, and moved (if at
> all). So, if you're building your own type, you can implement it to support
> value semantics, reference semantics, or a bit of both. That said, Mojo is
> designed with argument behaviors that default to value semantics, and it
> provides tight controls for reference semantics that avoid memory errors.
> 
> The controls over reference semantics are provided by the [value ownership
> model](/mojo/manual/values/ownership), but before we get into the syntax
> and rules for that, it's important that you understand the principles of value
> semantics. Generally, it means that each variable has unique access to a value,
> and any code outside the scope of that variable cannot modify its value.



---

# Level 0: Raw

```
struct String:
    var ptr: RawPointer
    ... 

fn main():
    var x = String("hello, world!")
```

```
fn main():
    # step 0: Allocate enough heap memory `var x: String`
    var uninitialized_ptr = RawPointer().alloc(ENOUGH_SPACE)
    # step 1: Initialize
    var ptr = uninitialize_ptr.write("hello, world!")
    # step 2: Assign
    var x = ptr
```

# Level 1: Add type parameter to RawPointer. C

# Level 2: Add lifetime parameter TypedPointer


---

Methods:

- shallow_copy() for descriptors
- deep_copy() for owning-like structs
- move()

---

## Posible solutions

1. Allow only a single use (or anything).
    - Deep copying is done explicitly if needed.
    - Shallow copying is the default, but can only happen once.

2. Always deep-copy by default.
    - Easier for new-comers.
    - Can lead to unnecessary copies.
    - We could offer ~ for shallow copy

3. Mandatory deep vs shallow indicator always. (@ for deep, ~ for shallow)
    (igual solo permitir shallow once, as the last use)
    - More explicit.

---

> [!BUG]
> Pero qué pasa entonces si pasas un ArrayView y se copia?
> En realidad no debería copiarse sus datos subyacentes.
> Pero claro, si hiciste keep los datos con el ArrayView, y luego haces copy, y
> luego deinit del original, se pierde la referencia.
> Entonces igual no hemos conseguido solucionar nada en nuestro lenguaje no?


Solución:

- Los tipos que almacenan la información (DynamicArray), implementan copy() haciendo
  deep copy de sus datos.

- Los tipos que son vistas (ArrayView), implementan copy() usando un ReferenceCounting
  para los datos a los que apuntan, y copiando solo el puntero y el length.

    Pensar Thread-safety: dos variantes:
    - SharedView con contador atómico (multi-hilo).
    - LeasedView con contador no-atómico (mono-hilo).

---

Valorar que &Array realmente sea un ArrayView

---

> [!check]
> ginger bill dice: I don't want to define my lifetimes based on my
> value, I want to be based on control flow (this loop, this function)

