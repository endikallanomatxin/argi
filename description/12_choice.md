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
