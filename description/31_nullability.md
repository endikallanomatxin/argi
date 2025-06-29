## Nullability. Optional types

Los tipos no pueden ser nulos. En su lugar, se utilizan enums.

```
Nullable<#T : Type> : Type = choice [
	..null
	..some(T)
]
```

You can get the value inside an option with `.unwrap()`.
If you unwrap a value that is `None`, the program will panic.

Para evitar que paniquee, se puede usar unwrap_or("Valor alternativo").




You can use `?` to declare a nullable type and to check if it is null.

```rg
my_function(input: ?Int = ..null) {
	if input? {
		// Do something
	} else {
		// Do something else
	}
}
```

### Orelse

En zig se puede hacer:

```zig
const display = c.XOpenDisplay("") orelse {
	std.log.err("Could not open display");
	return error.XOpenDisplayFailed;
};
```

Pensar si queremos algo asi.

