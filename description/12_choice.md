# Choice

Hay dos capas relacionadas:
- `choice` con payloads, como suma etiquetada cerrada
- `choice options` libres, que luego se componen en `choices` abiertos/cerrados

## Choice with payload

El payload de una variante puede ser cualquier `Type`, no solo un struct.

```rg
MaybeInt : Type = (
    ..none
    ..some Int32
)

SpanOrEnd : Type = (
    ..end
    ..span (.start: UIntNative, .end: UIntNative)
)
```

La sintaxis canónica de construcción es prefija:

```rg
a ::= ..none
b ::= ..some 123
c ::= ..span (.start = 3, .end = 8)
```

`..variant expr` consume la expresión completa del payload. Por ejemplo,
`..some a + b` significa `..some (a + b)`.

Si el payload es un struct, `..variant (...)` no es una llamada especial de
variante: simplemente es `..variant <expr_struct_literal>`.

## Match and payload access

`match` bindea el payload con su tipo real:

```rg
match b {
    ..none {
    }
    ..some n {
        use n
    }
}

match c {
    ..end {
    }
    ..span s {
        use s.start
    }
}
```

Los payload bindings pueden declarar explícitamente su modo dentro del patrón:

```rg
match value {
    ..some payload {
        use payload
    }
}

match value {
    ..some & payload {
        use payload&
    }
}

match value {
    ..some $& payload {
        payload& = other_value
    }
}

match value {
    ..some ~ payload {
        consume(payload)
    }
}
```

Reglas:
- `payload` es binding por valor
- `& payload` es binding por referencia read-only, de tipo `&T`
- `$& payload` es binding por referencia mutable, de tipo `$&T`
- `~ payload` mueve el payload; si el scrutinee es un binding existente, el
  `match` lo consume
- `_` ignora el payload

Además, `choice_value..variant` proyecta directamente el payload tipado de esa
variante:

```rg
n ::= b..some
s ::= c..span
print(.value = c..span.start)
```

Si la variante no tiene payload, `choice_value..variant` es error.

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

Chequeo de variante:

```rg
if is(.value = x, .variant = ..ok) {
}

if is(x, ..ok) {
}

if x == ..ok {
}
```

`is` acepta la forma nominal y la forma posicional `(value, variant)`. `==` y
`!=` pueden usarse directamente contra un literal `..variant` cuando el otro
lado ya tiene tipo `choice`; esto compara solo el tag e ignora el payload.

`match` sigue siendo la herramienta principal cuando interesa cubrir el conjunto
cerrado completo.
