# Syntax overview

## Comments

```
-- One line comments

---
Multiline comments for lengthier explanations
**They allow for markdown syntax**.
---

--*
Nestable comments?
*--

--- Doc comments, like zig
```

Hacer que no haya comentarios multilinea podría hacer que se
pueda tokenizar todo en paralelo.

## Variable and constant declaration

```
PI          :  Float = 3.141592653  -- Declares a constant
my_variable :: Int   = 42           -- Declares a variable
```

The declaration syntax has two delimeters:

- First, the type annotation delimeter. There are two options:
	- `:` for constants
	- `::` for variables
	When type is omitted, it is inferred from the value.

- Second, the value assignment delimeter. Always ` = `.

> [!NOTE]
> When a struct is constant, you are not allowed to:
> - Reassign its name
> - Reassign its fields
> - Create mutable pointers to it
> Con eso debería valer, porque las funciones que lo modifiquen necesitan un
> puntero mutable a la struct.

> [!CHECK]
> La sintaxis que usan odin y jai está bastante bien, porque `::` se interpreta
> como promesas que le haces al compilador y cuando ves `=` ves que lo que
> estás haciendo es una asignación, que es una instrucción. Esa diferencia me
> gusta.
>
> Igual tengo que explorar como de distinto es:
> - Declarar una función en top level, versus una variable que contiene una función
> - Declarar una constante como promesa al compilador, versus como una variable
>   normal que no se muta
> Si esas cosas son muy diferentes, entonces la sintaxis de odin y jai me gusta
> más.
> Darle una vuelta.


## Code blocks

Everything between `{ }` is considered a code block.

Every code block has its own scope.

This is also used for loops and conditional, so locally declared variables are not accessible outside the block.
This forces the good practice of declaring variables before loops and conditionals, instead of inside them.

> [!CHECK]
> Valorar que los bloques de código no puedan tomar nada de fuera como en Jai.
> Pero pensar una sintaxis cómoda para autollamar un bloque rollo función
> anónima. Es todavía más higiénico, pero pensar en como hacerlo sencillo.

> [!NOTE]
> En go, si hacer `v1, v2 := ...` dentro de un bloque, eso no declara solo las
> no declaradas, sino todas, haciendo que si una existía de antes, se eclipse.
> En nuestro lenguaje eso no debería pasar, si existe fuera, entonces no se
> re-declara si se hacen varias a la vez. Solo cuando se hace una.


## Functions

Functions are declared similar to variables or constants.

They just contain a couple of structs after the name, separated by an arrow:

```
add [.a: Int, .b: Int] -> [.c: Int] := {
	c = a + b
	return c
}
```

> [!TODO] En el cuerpo deberíamos usar c o .c?

When a function is called, you can omit the names of the fields when you specify all of them in the correct order:

```
result = add [1, 2]
```

> [!FIX] Como diferenciamos entonces entre un struct literal y un list literal?
> Igual que no exista list literal, y cuando crees una lista siempre parta de un struct literal?
> Pensar como solucionar esto para que no haya que poner siempre el nombre de los campos.


The type of the function would be: ` Function [Int, Int] -> [Int] `.

Anonymous functions can be defined like here:

```
some_function_that_needs_another_function(
	[.a: Int, .b: Int] -> [.c: Int] := {
		c = a + b
	},
	"Some other argument"
)
```

>[!IDEA] in and out reserved words for the input and output of the function.
> Podría dar lugar a una sintaxis muy cómoda para operaciones simples en funciones unarias.
> ```
> some_function_that_needs_another_function(
>     Int -> Int := { out = in^2 },
>     "Some other argument"
> )
> ```
> Gracias a eso, igual podríamos directamente no usar nunca `return` a no ser que quieras hacerlo en medio del programa.


## Generics

The language has generics.

Generics are different from functions in that they do not have multiple dispatch.

```
MyGenericType<# t: Type> : Type = struct [
	datos : List(t)
]
```

> [!TODO] Pensar en la sintaxis de inicialización de instancias de tipos.

> [!BUG] Tipos con generics en el input de una función
> El lenguaje tiene que ser lo suficientemente inteligente para saber que:
> `Vector<Int64>` cumple `Vector<Number>`, aunque no sea un subtipo directamente, sino en sus campos.
> Por lo general, si el generic del input tiene un valor que cuadra con el generic, entonces se toma como un requisito para cumplir el tipo. Si en cambio tiene una variable que no está asignada a nada, entonces en un parámetro de entrada adicional.

> [!BUG]
> El documento menciona “monomorfización” pero también AnyStruct e introspección; si mezclas open sum (choice) con dynamic dispatch los tiempos de compilación explotan.
> Sugerencia
> Decide un límites: todo lo que esté en genéricos → monomorfizado; todo lo que vaya por Abstract → tabla de v-funcs simple, no MRO complejo.
