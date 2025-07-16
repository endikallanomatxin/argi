# Errors

Copiar Zig, es el mejor.
Añadirle anyhow crate de Rust, para añadir contexto a los errores.

>[!QUOTE]
>The ptimeagen dice que cree que como lo hace zig le gusta más.
> https://www.youtube.com/watch?v=Epwlk4B90vk


## Error types

```
MyError : Error = "Some message"
```


## Error sets

```
my_error_set : ErrorSet = (
	error1
	error2
	error3
)
```

You can coerce an error from a subset to a superset, but you cannot coerce an
error from a superset to a subset.


## Error unions

```
Errable#(.t: Type, .e: Type) : Type = (
	..Ok    (t)  -- Success
	..Error (e)  -- Fail
)
```

An error set type and normal type can be combined with the ! binary operator to
form an error union type. You are likely to use an error union type more often
than an error set type by itself.

`!Int` se convierte en `AnyErrorSet!Int`.


### Unwrapping

As with Nullables, you can match or check the union regularly, but there are
builtin operators for unwrapping:

```
foo = errable_foo unwrap_or 0

foo = errable_foo unwrap_or_do {
    system.terminal | print ($&, errable_foo..Error | cast)
}
```

Cuando un error se castea a un string, se imprime el mensaje de error y el stack trace, con colorines.

> [!IDEA]
> Estaría bien que te imprimiera también las variables de input de la función
> que ha errado (siempre que su serialización sea menor que 1000 chars)


### Return err if errs

If you are inside a function that returns an Errable and you are calling a function that returns an Errable.

- If you do:`my_func () !`
	- If it doesn't err, it continues.
	- If it errs, it immediately returns the error. (like Rust, y como try en zig)
		Incluye siempre un stack trace y las variables que han dado lugar a ese error.
- If you do:`my_func () !! "Something"` you can add some context. (like anyhow rust crate)

