## Errors

Copiar Zig, es el mejor.
Añadirle anyhow crate de Rust, para añadir contexto a los errores.

>[!QUOTE]
>The ptimeagen dice que cree que como lo hace zig le gusta más.
> https://www.youtube.com/watch?v=Epwlk4B90vk


#### Error sets

```
my_error_set : ErrorSet = [
	error1
	error2
	error3
]
```

You can coerce an error from a subset to a superset, but you cannot coerce an error from a superset to a subset.


#### Error unions

```
Errable<#T: Type, #E: Type> : Type = choice [
	..Ok    (T)  -- Success
	..Error (E)  -- Fail
]
```

An error set type and normal type can be combined with the ! binary operator to form an error union type. You are likely to use an error union type more often than an error set type by itself.

`!Int` se convierte en `AnyErrorSet!Int`.


The four methods to easily check are `.is_some()`, `is_none()`, `is_ok()`, and `is_error()`.
You can unpack an Errable with `.unwrap()`.


If you are inside a function that returns an Errable() and you are calling a function that returns an Errable.

- If you do:`my_func()!`
	- If it doesn't err, it continues.
	- If it errs, it immediately returns the error. (like Rust, y como try en zig)
		Incluye siempre un stack trace y las variables que han dado lugar a ese error.
- If you do:`my_func()!!("Something")` you can add some context. (like anyhow rust crate)


Para catchear el error, hay un método catch(). Que lo imprime por la terminal, con todo el trace, con colorines por defecto. Te imprime también las variables de input de la función que ha errado (siempre que su serialización sea menor que 1000 chars)

>[!QUESTION] Named return arguments
>Hay que pensar como se declaran named return types dentro del Errable()
>Que ArgumentList sea un  `#type`. Que Errable() usa para generar el struct Success.?




### Panic

Más bien para desarollo.
No debería usarse en librerías.

### Warnings


### Deprecations

Marking some functions or types of a module as deprecated, no raise a warning.
