## Nullability. Optional types

Los tipos no pueden ser nulos. En su lugar, se utilizan enums.

```
Nullable<#T : Type> :: Type = choice [
	..null
	..some(T)
]
```

You can get the value inside an option with `.unwrap()`.
If you unwrap a value that is `None`, the program will panic.


You can use `?` to declare a nullable type and to check if it is null.

```rg
my_function(input: ?Int = ..null) {
	if input? { // Do something }
	// Do something else
}
```


