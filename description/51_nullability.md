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
    use(value)
}
```

`value?` se desazucara a `is(.value = value, .variant = ..some)`.

Dentro del branch `then` de ese `if`, si `T` es `ImplicitlyCopyable`, `value`
se estrecha idiomáticamente a `T` mediante una copia implícita. Para los demás
payloads hay que seguir usando `match`, acceso explícito al payload, o una
copia explícita compatible.

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

Para el caso lazy existe `unwrap_or_do`:

```rg
answer ::= maybe_answer unwrap_or_do {
    0
}
```

Aquí el bloque solo se evalúa si el valor es `..none`. La última expresión del
bloque determina el valor producido.
