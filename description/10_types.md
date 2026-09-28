# Types


## Naming

Types are named using PascalCase, and variables are named using snake_case.


## Type casting

Types are casted using the cast function.

- With multiple dispatch on the return type:

    ```
    cast (t: MyType) -> (s: String) := {
        ...
    }

    print( "My type:" + my_var|cast(_) )
    ```


- With multiple dispatch using `==`:

    ```
    cast (.t: MyType, .t: Type == String) -> (.s: String) := {
        ...
    }

    print( "My type:" + my_var|cast(_, String) )
    ```

- With multiple dispatch without using `==`, all types that can be cast must
occur inside the same function, for example in a `switch`. This is
not very extensible.

- With generics:

	```
	cast#(.t: Type) (.v: t) -> (s: String) := {
		...
	}

	print( "My type:" + my_var|cast#(typeof(my_var))(_) )
	```

- Using the init function:

	```
	my_string := String(my_var)
	```

	```
	init (s: $&String, v: MyType) -> () := {
		...
	}
	```

> [!TODO] Decide how to do this with multiple dispatch.

It is resolved through multiple dispatch.

Types are not automatically casted for arithmetic operations. 

Low-level casts that reinterpret addresses should use `UIntNative` as the
canonical integer type for pointer-sized values.


## Type checking

Types are nominal, not structural.


It is checked at compiletime.

```
#type(some_variable) == Int32
```

> [!TODO]
> If we want compile-time introspection on abstracts or contracts, define
> dedicated syntax for it instead of reusing `implements`, which is currently
> a declaration.

> [!TODO]
> Subtyping of `List#(.t: User)` vs. `List#(.t: Person)` (variance).

Inline declaration requires commas, but they can be ommited when using new lines.

## Alias

This uses the same syntax as type definitions.

```
Name : Type = String  -- Is this the abstract or the type?
```

Aliases are valid inputs to functions that take the underlying type.

> Is this safe?
> This could be useful for aliases:
> Go introduced `~` (tilde) to indicate an underlying type. `T` can then be any
> type whose underlying type is `int`, `float64`, and so on.
> Perhaps it is better to be strict so this feature remains useful.
> We have not yet decided whether automatic casting is a good idea.


## Private vs. Public

Everything is public by default to make it easier for beginners.

To make variables private, just use:
- `_name_surname` for variables in snake_case
- `nameSurname` for variables in PascalCase



## Notes

- UTF8 names? to insert LaTeX symbols: `\delta` + Tab. (from julia)
- If you write `x: float` and then `x = 1`, it understands that you mean `1.0`. (From Odin.)
- `x, y = y, x` must be supported.
