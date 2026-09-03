## Approaches to copying

Algunos tipos (archivos, sockets, dispositivos de hardware, semáfores, GPU
buffers...) no tiene sentido definir una copia. En estos casos,
directamente no se puede pasar por valor, solo con un puntero. Así eres
extra-explícito. Gracias a que la copia requiera una implementación explícita,
da la oportunidad de gestionarlo adecuadamente.

### Working direction

La dirección que mejor encaja con el resto del lenguaje es esta:

- `copy()` es la única operación de copia a nivel de lenguaje.
- Sólo un tipo que implementa explícitamente `ImplicitlyCopyable` se copia
  implícitamente al usar un named value donde se adquiere otro valor.
- Implementar `InfalliblyCopyable` permite `copy(&value)`, pero no activa la
  copia implícita.
- Implementar `FalliblyCopyable` permite una copia explícita que devuelve
  `Errable`; nunca activa una copia implícita.
- Si el tipo no es `ImplicitlyCopyable`, el uso plano es un error: hay que
  elegir `copy(&value)` o transferencia explícita con `~value`.
- La promesa semántica de `copy()` es siempre la misma: producir un valor
  independiente según el significado de ese tipo.
- Para tipos owners, eso significa una copia profunda de sus datos; no
  consideramos `shallow_copy()` como operación general del lenguaje, porque
  tendería a desmembrar la semántica de los tipos y a introducir aliasing
  accidental.

Esto encaja mejor que exponer varias operaciones como `deep_copy()` o
`shallow_copy()` en la superficie del lenguaje.

Toda copia, implícita o explícita, tiene que significar independencia lógica.
La transferencia de ownership nunca se infiere según el tipo.

```
m1 : Map = ()
m2 = copy(&m1)
```

### Different categories of types

- Owning types

    Su `copy()` normalmente duplica los datos que poseen.
    Tienen `init()` y `deinit()`.
    Ejemplos: `String`, `DynamicArray`, `HashMap`.

- Referencing types (views...)

    No deberían fingir ownership de los datos a los que apuntan.
    Si implementan `copy()`, esa copia debe preservar el significado de vista,
    no convertir silenciosamente la vista en un owner.

> [!BUG] Some types can be both
> (linked list nodes, graph nodes, several types that reference others and own some data)
> How should we handle that?


> [!BUG]
> Pero qué pasa entonces si pasas un `ArrayView` y se copia?
> En realidad no debería copiarse sus datos subyacentes.
> Pero claro, si hiciste `keep` de los datos con el `ArrayView`, y luego haces
> `copy()`, y luego `deinit()` del original, se pierde la referencia.
> Entonces igual no hemos conseguido solucionar nada en nuestro lenguaje, ¿no?


idea de solución:

- Los tipos que almacenan la información (`DynamicArray`) implementan `copy()`
  duplicando sus datos.

- Los tipos que son vistas (`ArrayView`) o bien no implementan `copy()`, o la
  implementan con una semántica explícita de vista retenida.

    Pensar thread-safety: dos variantes posibles:
    - `SharedView` con contador atómico (multi-hilo).
    - `LeasedView` con contador no atómico (mono-hilo).
