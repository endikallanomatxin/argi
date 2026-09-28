## Nullability. Optional types

Nullability is modeled with `Nullable#(.t: T)`:

```rg
Nullable#(.t: Type) : Type = (
    =..none
    ..some(.value: t)
)
```

There is syntactic sugar for the common form:

```rg
value : ?Int32 = ..some(.value = 5)
```

`?T` desugars to `Nullable#(.t: T)`.

Quick presence check:

```rg
if value? {
    use(value)
}
```

`value?` desugars to `is(.value = value, .variant = ..some)`.

Inside that `if` statement's `then` branch, if `T` is `ImplicitlyCopyable`,
`value` is idiomatically narrowed to `T` through an implicit copy. For other
payloads, continue to use `match`, explicit payload access, or a compatible
explicit copy.

Regular pattern matching is also available:

```rg
match value {
    ..none {
    }
    ..some payload {
        use(payload.value)
    }
}
```

`unwrap_or` is also available:

```rg
answer ::= maybe_answer unwrap_or 0
```

`unwrap_or` is a language operator for `Nullable`: it returns the value from
`..some`, or the fallback when the value is `..none`.

For lazy evaluation, use `unwrap_or_do`:

```rg
answer ::= maybe_answer unwrap_or_do {
    0
}
```

The block is evaluated only when the value is `..none`. Its final expression
determines the result.
