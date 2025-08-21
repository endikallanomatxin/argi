# Typesets for order.

Los interfaces:

- Obligan a especificar explícitamente qué tipos lo componen.

- Permiten definir un tipo por defecto, que será el que se inicialice si se usa
  como tipo al ser declarado.

- Se pueden componer.

- Se pueden extender fuera de sus módulos de origen.


```
Number : TypeSet = (
    Integer,
    Float...
)
```

> [!NOTE] Tipos con generics en el input de una función
>
> El lenguaje tiene que ser lo suficientemente inteligente para saber que:
> `Vector#(Int64)` cumple `Vector#(Number)`, aunque no sea un subtipo
> directamente, sino en sus campos.
>
> Por lo general, si el generic del input tiene un valor que cuadra con el
> generic, entonces se toma como un requisito para cumplir el tipo. Si en
> cambio tiene una variable que no está asignada a nada, entonces en un
> parámetro de entrada adicional.
