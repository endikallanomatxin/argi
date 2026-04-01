`Nullable` is represented as a generic choice type:

```rg
Nullable #(.t: Type) : Type = (
    =..none
    ..some(.value: t)
)
```

Current surface sugar:
- `?T` lowers to `Nullable#(.t: T)`
- `value?` lowers to `is(.value = value, .variant = ..some)`
- inside `if value? { ... }`, copyable payloads narrow to `T` within the `then` block
- `value unwrap_or fallback` unwraps `..some(.value)` or yields the fallback
- `value unwrap_or_do { ... }` evaluates the block only on `..none`
