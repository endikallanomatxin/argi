# Real number abstraction

[!IDEA] Exploratory design sketch; this is not an executable module.

```text
Real : Abstract = (
    operator +(.a: Self, .b: Self) -> (.value: Self)
    operator -(.a: Self, .b: Self) -> (.value: Self)
    operator *(.a: Self, .b: Self) -> (.value: Self)
    operator /(.a: Self, .b: Self) -> (.value: Self)
    operator %(.a: Self, .b: Self) -> (.value: Self)
    operator ^(.a: Self, .b: Self) -> (.value: Self)
    ...
)

Int implements Real
Float implements Real
```
