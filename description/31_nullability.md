## Nullability. Optional types

Los tipos no pueden ser nulos. En su lugar, se utilizan enums.

```
Nullable#(.t: Type) : Type = choice (
	..null
	..some T
)
```

```rg
my_nullable? -- Returns true or false
```

Se puede hacer matching:

```rg
match my_nullable {
  ..some v => {
	// `v` es un Int
	use v;
  }
  ..null => {
	// gestionar el caso nulo
  }
}
```

También se puede unwrapear:

```rg
my_value = my_nullable unwrap_or 0
```

```rg
my_value = my_nullable unwrap_or_do {
	// gestionar el caso nulo
	return 0
}
```

(Como el orelse de Zig)

Son operadores, porque si se plantean como funciones, el piping queda muy tedioso.

