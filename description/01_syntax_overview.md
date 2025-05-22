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
```

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



## Code blocks

Everything between `{ }` is considered a code block.

Se hace implicit return de la última línea, así se puede usar como paréntesis para definir el orden de evaluación de las expresiones. (from gleam)

```
c = {a + b}^2
```

> [!BUG]
> Si haces return implícito incluso no poniendo tipo de retorno,
> entonces no puedes usarlo para fors, ifs y demás porque siempre retornarán algo.
> Igual puede hacerse que si lo último es una expresión se retorna, pero si es una declaración no?
> Pero tiene sentido que se pueda retornar algo, sin haber puesto que retorna algo? Eso fastidia la sintaxis de las funciones.

Every code block has its own scope.

This is also used for loops and conditional, so locally declared variables are not accessible outside the block.
This forces the good practice of declaring variables before loops and conditionals, instead of inside them.

If a code block has a return value, it has to be declared before the block inside ().

```
my_var := (a: Int, b: Int) {
	a + b
}
```

> [!BUG] This is not coherent with the {} as parentheses for the order of evaluation.
> Igual hay que hacerlo opcional? Que sea inferido si no se pone nada?
> No me gusta eso.

> [!NOTE]
> En go, si hacer `v1, v2 := ...` dentro de un bloque, eso no declara solo las no declaradas, sino todas, haciendo que si una existía de antes, se eclipse.
> En nuestro lenguaje eso no debería pasar, si existe fuera, entonces no se re-declara si se hacen varias a la vez. Solo cuando se hace una.


## Functions

Functions are declared similar to variables or constants.

It just has `(...)` after the name, with the arguments inside.

```
my_function(a: Int) := {
	...
}
```

Return arguments go with the code block. They can be named.

```
sum_two_numbers(A: Int, B: Int) := (C: Int) {
	C = A + B
	return C
}
```

> [!NOTE]
> They can be constant. Declaration and initialization can be done at once, or separately.
> It rust this can be done for example. You just have to not use the variable before its initialization.

If we had to say it, the type of the function would be: ` Func<Int, Int -> Int> `

Anonymous functions can be defined like here:

```
some_function_that_needs_another_function(
	(a: Int, b: Int) := (c: Int) {
		c = a + b
	},
	"Some other argument"
)
```

> [!TODO] Pensar si queremos queremos permitir esta sintaxis.
> Si una variable tiene parámetros, pero no es un type, en realidad es una función, que devuelve el valor parametrizado que tiene en la derecha. Por lo que siempre que veas () despues de un nombre en una declaración, sabes que se trata de una función.


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
