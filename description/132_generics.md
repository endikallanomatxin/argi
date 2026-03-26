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

## Constraint Design

There are two plausible paradigms for generic constraints in Argi.

The intended order is:

- start with the simpler one
- push it as far as it naturally goes through composition
- only move to the richer one if real use cases prove it necessary

### Option A: bounded type parameters

This is the compact system:

```argi
sum#(.t: Type: Number) (.xs: []t) -> (.result: t)
BufferedReader#(.base_type: Type: Reader) : Type = ...
```

Meaning:

- `.t` is still a `Type` parameter
- `Number` or `Reader` is not the parameter type itself
- it is a static check saying that the concrete type bound to that parameter
  must implement the given abstract

This option is attractive because it keeps everything in one place:

- `#(...)` declares the comptime parameters
- the `: Abstract` suffix expresses a simple implements-check

This is enough for many useful cases:

- buffered wrappers over `Reader` / `Writer`
- numeric algorithms over `Number`
- generic containers constrained by `Indexable`, `Resizable`, etc.

It is also important that many structural relationships do not need any extra
constraint syntax at all. They can already be expressed by reusing the same
comptime parameters directly in the signature:

```argi
multiply#(
    .t: Type,
    .left_rows: UIntNative,
    .shared: UIntNative,
    .right_cols: UIntNative,
)(
    .left: Matrix#(.t: t, .rows = left_rows, .cols = shared),
    .right: Matrix#(.t: t, .rows = shared, .cols = right_cols),
) -> (
    .result: Matrix#(.t: t, .rows = left_rows, .cols = right_cols)
)
```

That matters because it means matrix shapes and many other compile-time
relationships can often be modeled without a separate relational language.

Current preference:

- Argi should start with this option
- it should only be replaced if it stops being sufficient

### Option B: relational constraints with `where(...)`

If Option A stops being enough, the next step should be a separate relational
checking layer.

The core idea would be:

- `#(...)` introduces comptime variables
- `where(...)` checks relations between those variables afterwards

For example:

```argi
copy#(.r: Type, .w: Type)
where(
    r implements Reader,
    w implements Writer,
)(
    .reader: $&r,
    .writer: $&w,
) -> ()
```

The exact set of allowed predicates is still open, but if this direction is
ever taken it should be understood as:

- a checking layer over already-declared comptime parameters
- not a second, separate generics system

Its likely value would be cases that become awkward or impossible to express
cleanly with Option A alone, such as:

- expressing implements-checks outside the parameter declaration itself
- arithmetic relations between comptime values when those relations are not
  already encoded naturally in the signature
- future higher-order constraints if iterators, matrices or algebraic traits end
  up needing them

### Current stance

The language should proceed with Option A first.

Option B should stay documented as a reserved extension path for the future, but
it should not be introduced unless real library design pressure proves it is
needed.

In short:

- implement `#(.t: Type: SomeAbstract)` well
- keep pushing signature-based composition first
- only add `where(...)` if the simple bounded model is no longer enough


## Interación con Multiple Dispatch

* **Identidad** = `nombre + patrón de tipos de los parámetros`.
* El bloque `#(...)` **no** forma parte de la identidad; solo **declara** los genéricos usados.
* **Prohibido duplicar** la misma firma con o sin `#(...)` (redefinición).


## Interacción con Virtual types

* **Generics no van en la vtable.** Los métodos de vtable deben ser **monomórficos** tras borrar tipos.
