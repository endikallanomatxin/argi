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

Los payload bindings pueden declarar explícitamente su modo dentro del patrón:

```rg
match value {
    ..some(payload) {
        use payload
    }
}

match value {
    ..some(& payload) {
        use payload&
    }
}

match value {
    ..some($& payload) {
        payload& = other_value
    }
}

match value {
    ..some(~ payload) {
        consume(payload)
    }
}
```

Reglas:
- `(..payload)` es binding por valor
- `(..& payload)` es binding por referencia read-only, de tipo `&T`
- `(..$& payload)` es binding por referencia mutable, de tipo `$&T`
- `(..~ payload)` mueve el payload; si el scrutinee es un binding existente, el
  `match` lo consume
- `(.._)` ignora el payload

Esto evita préstamos implícitos mágicos: cada binding de payload declara
explícitamente si quiere valor, préstamo o move.

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
