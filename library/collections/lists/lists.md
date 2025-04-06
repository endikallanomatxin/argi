# Lists

List<#T>

- Array<#T>
    - BareStaticArray<#T, #N> -- With the minimum ammount of fields. Completely unmanaged.
    - StaticArray<#T, #N>
    - DynamicArray<#T>
        - CopyingDynamicArray<#T>  -- It contains a single list, fast indexing.
        - SegmentedDynamicArray<#T>  -- It contains a list of lists, slow indexing, but avoids copying.

- LinkedList<#T>
    - SinglyLinkedList<#T>
    - DoublyLinkedList<#T>
    - Rope<#T>  -- It is a linked list of arrays


append(), pop(), get(index), set(index, value))


Unincorporated ideas from zig:

- Alignment
    En zig hay tipos que son ArrayListAligned, por ejempo, que tienen ademas su info, un campo extra para especificar el alignment.
    Igual una keyword? O un wrapper? O tipos específicos?
    O que todos tengan alignment? Y que en lugar de Aligned, se llamen WithoutAlignment?

- Unmanaged
    En zig también hay algunos tipos con Unmanaged en el nombre, que no contienen un allocator y entonces hay que pasarlo cada vez que se llama a una función. No sé si me gusta mucho.

- BoundedArray.
    Es un array de tamaño determinado en runtime, pero que su tamaño máximo se conoce en compilación.
    En realidad es lo mismo que un DynamicArray, pero con un capacity inicial.

- MultiArrayList. Struct of arrays
    Esto es para tener un struct de arrays en vez de un array de structs.
    Optimiza el uso en memoria reduciendo el padding, y mejora el cache.



#### Exploración de un wrapper para Alignment y Allocator

```
Alignment :: Type = [
    ..Default
    ..Compact
]

-- Las funciones de los tipos podrían tener un campo alignment, que tuviera el valor por defecto ..Default
-- Así los tipos sin nada, ya tienen el alignment por defecto.
-- Si en cambio quieres un alignment distinto, entonces lo pones con un wrapper:

ListAlignmentManager<#T :: Type> :: Type = [
    .data      : T
    .alignment : Alignment
]

-- Este se encarga de ponerle a las funciones a las que llames el alignment que le pases.


```

Esto igual se sale mucho de la simplicidad que buscaba.

¿Qué pinta tiene la implementación de algo así? Como podría definirse un wrapper en mi lenguaje?


