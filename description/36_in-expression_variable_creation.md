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
      SketchBuilder()
    | trapezoid(&_, 4, 3, 90)
    | fillet(&_, 0.25)
    | extrude(&_, 0.1)
    | finish(&_)
```

Función que necesita referencia para paralelizar:

```
result :=
      load_png("image.png")
    | keep _ with result
    | parallel_process_that_only_reads(&_)
    | parallel_process_that_writes(~&_)
```

