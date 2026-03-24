`Nullable` is represented as a generic choice type:

```rg
Nullable #(.t: Type) : Type = (
    =..none
    ..some(.value: t)
)
```
