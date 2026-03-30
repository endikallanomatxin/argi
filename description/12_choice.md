# Choice

Hay dos capas relacionadas:
- `choice` con payloads, como suma etiquetada cerrada
- `choice options` libres, que luego se componen en `choices` abiertos/cerrados

## Choice with payload

```rg
Nullable#(.t: Type) : Type = (
    =..none
    ..some(.value: t)
)
```

```rg
match value {
    ..none {
    }
    ..some(payload) {
        use payload
    }
}
```

> [!TODO]
> Sigue abierto el diseño exacto de los bindings de payload en `match` para
> tipos no copyable.
>
> Hoy `..variant(name)` debe entenderse como binding por valor. Si el payload no
> implementa `copy()`, ese binding no debería usarse como atajo mágico a un
> préstamo implícito.
>
> Mientras no se diseñe una sintaxis y semántica mejores para borrowed payload
> bindings, el camino estable es:
> - usar `..variant(_)` para ramificar,
> - y acceder al payload refinado desde el scrutinee dentro de la rama
>   (`value..variant...`).
>
> Queda pendiente decidir una forma explícita y coherente de inspeccionar
> payloads no copyable sin introducir magia semántica en `match`.

## Choice options

Una opción libre se declara a nivel de módulo:

```rg
..file_not_found
..permission_denied
```

Cada opción:
- es nominal
- tiene id numérico único asignado por el compilador
- puede formar parte de varios `choices`

## Open choices

Se forman con listas cerradas de opciones:

```rg
reason : (..file_not_found, ..permission_denied) = ..file_not_found
```

Esto se usa especialmente para:
- razones de error
- conjuntos exhaustivos de estados
- composición de APIs que propagan subconjuntos hacia supersets

## Access and checks

Valores `choice` con payload:

```rg
x..ok
```

Chequeo de variante:

```rg
if is(.value = x, .variant = ..ok) {
}
```

`match` sigue siendo la herramienta principal cuando interesa cubrir el conjunto
cerrado completo.
