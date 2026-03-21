# Compiletime-parameters

- Se monomorfizan.
- Se pueden no poner y el compilador los infiere.
- Mismo sistema para tipos y funciones.
- Pueden tener valores por defecto.


## Sintaxis

### Declaración

Usa `#( … )` para **declarar** parámetros genéricos. El binder puede aparecer en:

* declaraciones de **tipos** y **abstracts**,
* **funciones** y **operadores**.

```argi
-- Tipo genérico
Vec#(.t: Type, .n: UIntNative) : Type = ( ... )

-- Función genérica
max#(.t: Type) (.a: t, .b: t) -> (.result: t) := {
    if a > b { result = a } else { result = b }
}
```

### Uso

```argi
let v : Vec#(.t: Float32, .n = 3) = (1.0, 2.0, 3.0)

let r := max#(.t: Int)(.a = x, .b = y)
```

For now the canonical documented form uses named generic arguments. Positional
generic arguments may still be considered later for ergonomics.


### Bounds

```argi
sum#(.t: Type: Number) (.xs: []t) -> (.result: t)
-- t debe implementar el abstract Number
```


> [!CHECK] Explorar la necesidad de `where`


## Interación con Multiple Dispatch

* **Identidad** = `nombre + patrón de tipos de los parámetros`.
* El bloque `#(...)` **no** forma parte de la identidad; solo **declara** los genéricos usados.
* **Prohibido duplicar** la misma firma con o sin `#(...)` (redefinición).


## Interacción con Virtual types

* **Generics no van en la vtable.** Los métodos de vtable deben ser **monomórficos** tras borrar tipos.

