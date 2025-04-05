
## Nullability. Optional types

Like in gleam:
`Nil` is not a valid value of any other types. Therefore, values in Gleam are not nullable. If the type of a value is `Nil` then it is the value `Nil`. If it is some other type then the value is not `Nil`.


```
Nullable<#T : Type> :: Type = choice [
	..None
	..Some(T)
]
```

O igual nullable.

We can get the value inside an option with `.unwrap()`. If you unwrap a value that is `None`, the program will panic.

