## Approaches to copying

Algunos tipos (archivos, sockets, dispositivos de hardware, semáfores, GPU
buffers...) no tiene sentido definir una deep copy. En estos casos,
directamente no se puede pasar por valor, solo con un puntero. Así eres
extra-explícito. Gracias a que la copia requiera una implementación explícita,
da la oportunidad de gestionarlo adecuadamente.

### A: Different copying methods

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

### B: Single copy method but different for different kinds of types

- Owning types

    **Can only be shallow-copied once. Transfering ownership**
    Have an init and deinit method.
    Examples: DynamicString, DynamicArray...

- Referencing types (views...)

    Should not be copied without extending the lifetime of the referenced data.

> [!BUG] Some types can be both
> (linked list nodes, graph nodes, several types that reference others and own some data)
> How should we handle that?


> [!BUG]
> Pero qué pasa entonces si pasas un ArrayView y se copia?
> En realidad no debería copiarse sus datos subyacentes.
> Pero claro, si hiciste keep los datos con el ArrayView, y luego haces copy, y
> luego deinit del original, se pierde la referencia.
> Entonces igual no hemos conseguido solucionar nada en nuestro lenguaje no?


idea de solución:

- Los tipos que almacenan la información (DynamicArray), implementan copy() haciendo
  deep copy de sus datos.

- Los tipos que son vistas (ArrayView), implementan copy() usando un ReferenceCounting
  para los datos a los que apuntan, y copiando solo el puntero y el length.

    Pensar Thread-safety: dos variantes:
    - SharedView con contador atómico (multi-hilo).
    - LeasedView con contador no-atómico (mono-hilo).

