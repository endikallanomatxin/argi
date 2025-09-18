# Types


## Naming

Types are named using PascalCase, and variables are named using snake_case.


## Type casting

Types are casted using the cast function.

- Con multiple dispatch en el return type:

    ```
    cast (t: MyType) -> (s: String) := {
        ...
    }

    print( "My type:" + my_var|cast(_) )
    ```


- Con multiple dispatch considerando ==:

    ```
    cast (.t: MyType, .t: Type == String) -> (.s: String) := {
        ...
    }

    print( "My type:" + my_var|cast(_, String) )
    ```

- Con multiple dispatch sin usar ==, obliga a que todos los tipos a los que se
puede castear ocurran dentro de la misma función, por ejemplo usando switch. Es
poco ampliable.

- Con generics:

	```
	cast#(.t: Type) (.v: t) -> (s: String) := {
		...
	}

	print( "My type:" + my_var|cast#(typeof(my_var))(_) )
	```


> [!TODO] Decidir como se hace esto usando multiple dispatch.

Se resuelve gracias al multiple dispatch.

Types are not automatically casted for arithmetic operations. 


## Type checking

Types are nominal, not structura.


It is checked at compiletime.

```
#type(some_variable) == Int32
#implements(some_variable, Int)
```

> [!TODO]
> Sub-typing de List<User> vs List<Person> (variancia).

Inline declaration requires commas, but they can be ommited when using new lines.

## Alias

Se hace con la misma sintaxis que para la definición de tipos.

```
Name : Type = String  -- Uff pero esto es el abstract o el tipo.
```

Los aliases son inputs válidos para funciones con input del tipo subyacente.

> Seguro?
> Esto para los aliases vendría bien:
> Go introdujo la posibilidad de usar `~` (tilde) para indicar subyacencia, o sea `T` puede ser cualquier tipo cuyo subyacente sea `int`, `float64`, etc.
> Igual conviene ser estricto para que realmente pueda ser útil.
> Pero bueno, todavía ni siquiera hemos decidido si el casting automático es bueno.


## Private vs. Public

Everything is public by default to make it easier for beginners.

To make variables private, just use:
- `_name_surname` for variables in snake_case
- `nameSurname` for variables in PascalCase



## Notes

- UTF8 names? to insert LaTeX symbols: `\delta` + Tab. (from julia)
- Si dices que `x: float` y luego dices `x = 1`, sabe que en realidad quieres decir `1.0`. (from Odin)
- `x, y = y, x` se tiene que poder hacer.

