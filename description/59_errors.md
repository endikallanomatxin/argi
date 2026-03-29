# Errors

Dirección general:
- Semántica de propagación y ergonomía en la línea de Zig.
- Posibilidad de añadir contexto útil al estilo anyhow de Rust.

>[!QUOTE]
>The ptimeagen dice que cree que como lo hace zig le gusta más.
> https://www.youtube.com/watch?v=Epwlk4B90vk


## Fundamento aceptado: errors as types

El fundamento aceptado es que la identidad del error sea su tipo.

- Un `ErrorReason` es un `Type` nominal.
- En principio será un tipo vacío.
- El `type id` hace el papel de identificador global del error, en la línea del
  efecto que tiene Zig con sus errors ligeros y fácilmente comparables.

Ejemplos conceptuales:

```
NotFound : Type = ()
PermissionDenied : Type = ()
InvalidNumber : Type = ()
```

Esto separa dos cosas:
- La identidad del error: el tipo.
- La traza y el contexto humano: información adicional opcional.


## Error values

```
Error : Type = (
	.reason: Type
	.trace: ErrorTrace
)
```

La forma concreta de `ErrorTrace` sigue abierta, pero la dirección aceptada es
que la traza viva dentro del propio valor `Error`.


## Error unions

```
Errable#(.t: Type, .reason: Type) : Type = (
	..ok(.value: t)    -- Success
	..error(.reason: e) -- Fail
)
```

An error set type and normal type can be combined with the ! binary operator to
form an error union type. You are likely to use an error union type more often
than an error set type by itself.

`!Int` se convierte en `AnyErrorSet!Int`.

Esto seguramente habrá que revisarlo para alinearlo con `errors as types`, pero
la idea general sigue siendo válida: `!T` representa “`T` o error”.


### Unwrapping

As with Nullables, you can match or check the union regularly, but there are
builtin operators for unwrapping:

```
foo = errable_foo unwrap_or 0

foo = errable_foo unwrap_or_do {
    system.terminal | print ($&, errable_foo..error | cast)
}
```

Cuando un error se castea a string, se debería imprimir de forma útil para
humanos, incluyendo razón y traza si existe.

> [!IDEA]
> Estaría bien que pudiera incluir también valores relevantes del contexto
> (inputs, path, token, etc.) si eso ayuda a entender qué está pasando.


### Return err if errs

If you are inside a function that returns an Errable and you are calling a function that returns an Errable.

- If you do:`my_func () !`
	- If it doesn't err, it continues.
	- If it errs, it immediately returns the error. (like Rust, y como try en zig)
- If you do:`my_func () !! "Something"` you can add some context. (like anyhow rust crate)

> Se permite en cualquier subexpresión (no solo en instrucción); ejemplo: line_len := read_line_into_buffer(.stdin = fd, .buffer = $&line)!.len.

> En funciones cuyo tipo de salida no es Errable, usar ! es error del compilador.

> ! hace short-circuit con ejecución de defers


## Tracing strategy

La dirección aceptada es que la traza viva dentro de `Error`.

`Error` debe ser autocontenido: además de la identidad del error en `.reason`,
lleva su `.trace`, que se puede ir ampliando al propagar el error o al añadir
contexto con operadores como `!!`.

Ventajas:
- Es la opción más natural y directa.
- El error se puede imprimir, pasar y devolver sin depender de capacidades
  adicionales.
- Encaja mejor con la idea de tratar el error como un valor normal del
  lenguaje.
- Hace más fácil definir un cast a string útil para humanos.

Coste asumido:
- Existe un overhead base incluso cuando no se quiere una traza rica.
- La representación concreta de `ErrorTrace` debe diseñarse para que ese coste
  siga siendo razonable.

> [!IDEA]
> Alternativa futura: `system.error_tracer` reached
>
> Se podría explorar una estrategia reached, por ejemplo
> `system.error_tracer`, que decida cómo se construye, amplía o ignora la
> traza.
>
> Posibles ventajas:
> - Permitir una estrategia con overhead casi nulo.
> - Permitir sobreescribir el mecanismo de traceado.
> - Separar la identidad del error de la política de observabilidad.
>
> Inconvenientes:
> - Es menos natural, porque la traza no vive simplemente dentro del error.
> - Hace depender parte de la experiencia de errores de una capability
>   reached.


## Errable as a monad

pensar en concatenar operaciones sobre errables (andthen, orelse…)
podria ser
and then: “|>”
or else: “|<“ o “|!”

Darle una vuelta.
