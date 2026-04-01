# Errors

Dirección aceptada:
- Propagación y ergonomía en la línea de Zig.
- Contexto y traza humana acumulable al propagar, en la línea de `anyhow`.
- La identidad del error ya no es un `Type` arbitrario: es una `choice option`
  nominal.

## Choice options

Una `choice option` se declara suelta:

```rg
..file_not_found
..permission_denied
..invalid_format
```

Semántica:
- Cada declaración define un símbolo nominal.
- El compilador asigna a cada opción un id numérico único durante la
  compilación.
- Ese id es la identidad real de la opción.
- El texto `..name` solo es la forma de referirse a ella.

No hay autodeclaración por uso:
- `..file_not_found` en posición de valor referencia una opción existente.
- Si no existe, es error.

## Open choices

Las opciones se agrupan en `choices` cerrados cuando hace falta tipado o
exhaustividad.

```rg
reason : (..file_not_found, ..permission_denied) = ..permission_denied
```

Un `choice` puede ser:
- anónimo, como en el ejemplo anterior
- nombrado, usando un alias o tipo del lenguaje

Los `choices` usados para errores son cerrados y finitos.

## Error values

La traza sigue viviendo dentro del propio error.

```rg
Error#(.reasons: Choice) : Type = (
    .reason: reasons
    .trace: ErrorTrace
)
```

Restricciones:
- `.reason` debe ser un `choice` sin payloads
- `.trace` mantiene el mecanismo actual de entradas de traza

## Error unions

`Errable` queda definido sobre un conjunto de razones:

```rg
Errable#(.t: Type, .reasons: Choice) : Type = (
    ..ok(.value: t)
    ..error(
        .reason: reasons
        .trace: ErrorTrace
    )
)
```

Consecuencias:
- una función declara el conjunto de razones que puede devolver
- `!` permite propagar un subconjunto hacia un superset compatible
- el remapeo de tags entre conjuntos distintos lo hace el compilador/codegen

Ejemplo:

```rg
..file_not_found
..permission_denied

read_file() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found))) := {
    result = ..error(.reason = ..file_not_found)
}

load_file() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found, ..permission_denied))) := {
    value := read_file()!
    result = ..ok(.value = value)
}
```

For the common single-result case there is also shorthand syntax:

```rg
load_file() -> !Int32 := {
    value := read_file()!
    result = ..ok(.value = value)
}
```

`-> !T` means a single output binding named `result` whose type is an `Errable`
returning `T`. In this special form, the compiler infers the reasons from the
body and closes the return `Errable` after semantic analysis.

The compiler can also infer a narrower subset of the declared reasons by
looking at the actual propagation and return sites in the function body. That
inferred subset is surfaced in tooling hover even when the full declared
`.reasons` are still written explicitly in source.

En `core`, la misma idea ya se usa para fallos de apertura, de sistema de
ficheros y de streams:

```rg
..file_open_failed
..path_open_failed
..stream_read_failed
..stream_write_failed
..stream_flush_failed
..stream_close_failed
..out_of_memory

open_read(.p: $&File, .path: CString)
    -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed)))

read_file(.self: &FileSystem, .path: StringView)
    -> (.result: Errable#(
        .t: String,
        .reasons: (..path_open_failed, ..stream_read_failed, ..stream_close_failed, ..out_of_memory),
    ))

read_byte(.self: $&Reader)
    -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed)))

write_byte(.self: $&Writer, .byte: UInt8)
    -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
```

`read_line()` y `read_file()` ya propagan `..out_of_memory` de forma explícita.
`read_line()` y `read_file()` delegan ya la creación y el crecimiento del buffer
en helpers fallibles de `String`.

En `core`, la dirección idiomática para operaciones de crecimiento o reserva ya
no es:
- puntero crudo + comparar con `0`
- `Bool` para decir si la reserva salió bien

Sino:
- `allocate_fallible(...) -> Errable#(.t: UIntNative, .reasons: (..out_of_memory))`
- helpers como `string_with_capacity(...)`
- operaciones de crecimiento que devuelven `Errable#(.t: Void, .reasons: (..out_of_memory))`

Eso ya se aplica en `String` y en las rutas fallibles de `DynamicArray`
(`push_growing`, `insert_growing`, `dynamic_array_grow_growing`).

EOF sigue fuera del canal de error:

```rg
ReadByte : Choice = (
    ..ok(.byte: UInt8)
    ..end
)
```

## Propagation

`!` y `!!`:
- hacen short-circuit
- ejecutan `defer`s
- añaden una entrada a la traza
- exigen que el `Errable` actual pueda representar todas las razones
  propagadas
- pueden usarse tanto en posición de expresión como como sentencia pura, por
  ejemplo `step()!`, cuando el valor `..ok` no interesa

Hoy ya se usan de forma normal en contextos de expresión comunes:
- bindings: `value := read_file()!`
- argumentos de llamada: `use(.x = read_int()!)`
- condiciones: `if ready()! { ... }`
- asignaciones: `cached = load()!`
- sentencias puras: `flush()!`

`!!` además adjunta contexto textual a la entrada de traza.

Dirección actual de la inferencia de reasons:
- la firma sigue escribiendo el conjunto completo declarado
- `-> !T` ya permite omitir `.reasons` en el caso especial de un único
  resultado `result`
- semántica calcula un subconjunto inferido a partir de `return`, asignaciones a
  outputs y propagaciones con `!` / `!!`
- el hover muestra ese subconjunto inferido para que se pueda consultar sin
  ruido extra en el código
- el siguiente paso será permitir omitir `.reasons` en más sitios una vez esta
  inferencia sea suficientemente robusta también entre módulos

## Exhaustividad

La exhaustividad se chequea contra un `choice` cerrado, no contra una opción
suelta.

Eso permite:
- `match` sobre `Errable`
- chequeos sobre `.reason`
- futuras mejoras de narrowing/resto de casos sin depender de strings ni tipos
  arbitrarios

Para inspeccionar un `Error` sin copiarlo, `match` puede bindear el payload por
referencia:

```rg
match result {
    ..ok _ {
    }
    ..error & err {
        match err&.reason {
            ..file_not_found {
                ...
            }
            ..permission_denied {
                ...
            }
        }
    }
}
```

## Runtime

En runtime:
- la razón de error viaja como tag de `choice`
- la identidad de cada opción viene de su id de compilación
- la traza sigue siendo un valor autocontenido dentro del error

La representación sigue siendo ligera, pero el tipado conserva el conjunto
exacto de razones disponible en cada frontera.
