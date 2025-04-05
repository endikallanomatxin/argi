## Errors

There are mostly two situations:

- Functions that return something is everything is successful but nothing if there is an error.
	For these: Hope/Expect/Errable (like Rust's result)
- Functions that always return as much as they can, but sometimes want to give a warning.
	For these: Status (like Go's err)

```
Errable<#T:: Type, #E:: Type> :: Type = choice [
	..Ok    (T)  -- Success
	..Error (E)  -- Fail
]
```

**Ergonomy**

If you are inside a function that returns a Hope() and you are calling a function that returns a hope.

- If you do:`my_func()?`
	- If it doesn't err, it continues.
	- If it errs, it immediately returns the error. (like Rust, y como try en zig)
		Incluye siempre un stack trace y las variables que han dado lugar a ese error.
- If you do:`my_func()??` 
- If you do:`my_func()??("Something")` you can add some context. (like anyhow rust crate)

The four methods to easily check are `.is_some()`, `is_none()`, `is_ok()`, and `is_error()`.

You can `.unwrap()`

Para catchear el error, hay un método catch(). Que lo imprime por la terminal, con todo el trace, con colorines por defecto. Te imprime también las variables de input de la función que ha errado (siempre que su serialización sea menor que 1000 chars)

>[!QUESTION] Named return arguments
>Hay que pensar como se declaran named return types dentro del Errable()
>Que ArgumentList sea un  `#type`. Que Errable() usa para generar el struct Success.?

>[!QUOTE]
>The ptimeagen dice que cree que como lo hace zig le gusta más.
> https://www.youtube.com/watch?v=Epwlk4B90vk

#### Error sets (like in zig)

Pensar en como implementar algo parecido.

### Panic

Más bien para desarollo.
No debería usarse en librerías.

### Warnings


### Deprecations

Marking some functions or types of a module as deprecated, no raise a warning.
