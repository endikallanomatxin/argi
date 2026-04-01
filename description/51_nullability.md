## Nullability. Optional types

La nullabilidad se modela sobre `Nullable#(.t: T)`:

```rg
Nullable#(.t: Type) : Type = (
    =..none
    ..some(.value: t)
)
```

Hay azúcar superficial para la forma común:

```rg
value : ?Int32 = ..some(.value = 5)
```

`?T` se desazucara a `Nullable#(.t: T)`.

Chequeo rápido de presencia:

```rg
if value? {
}
```

`value?` se desazucara a `is(.value = value, .variant = ..some)`.

Se puede hacer matching normal:

```rg
match value {
    ..none {
    }
    ..some payload {
        use(payload.value)
    }
}
```

Y también `unwrap_or`:

```rg
answer ::= maybe_answer unwrap_or 0
```

`unwrap_or` es un operador del lenguaje sobre `Nullable`: devuelve el valor de
`..some`, o el fallback cuando el valor es `..none`.

> [!TODO]
> `unwrap_or_do` sigue abierto. Para hacerlo limpio hacen falta bloques
> expresión o una forma equivalente de expresar el branch lazily sin meter una
> semántica especial ad hoc solo para nullables.
