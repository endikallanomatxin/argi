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

## Declaration

### Variables vs. constants

```
PI          :: Float = 3.141592653  -- Declares a constant
my_variable :  Int   = 42           -- Declares a variable
```

The declaration syntax has two delimeters:

- First, the type annotation delimeter. There are two options:
	- `::` for constants
	- `:` for variables
	When type is omitted, it is inferred from the value.

- Second, the value assignment delimeter. Always ` = `.

### Functions

Everything between `{ }` is considered the function body.

There is a unified syntax that allows for both generics and function arguments.

Everything after the name and between `( )` is considered arguments.

```
my_function(a: Int) ::= {
	...
}
```

Se ha
(En gleam, como se hace implicit return de la última linea, se puede usar para definir el orden de evaluación de las expresiones, en lugar de paréntesis.)

Return arguments in functions are defined before the function body. They can be named.

```
sum_two_numbers(A: Int, B: Int) :: Func(Int, Int -> Int) = (C: Int) {
	return A + B
}
```

Anonymous functions can be defined by:

```
some_function_that_needs_another_function(
	(a: Int, b: Int) ::= (c: Int) {
		c = a + b
	},
	"Some other argument"
)
```

Si una variable tiene parámetros, pero no es un type, en realidad es una función, que devuelve el valor parametrizado que tiene en la derecha. Por lo que siempre que veas () despues de un nombre en una declaración, sabes que se trata de una función.

#### Scope

Every function body has its own scope.

Also for if, for, while, match... It makes local variables not to be accessible outside the block.
But that forces you to write cleaner code.

>En go, si hacer v1, v2 := dentro de un bloque, eso no declara solo las no declaradas, sino todas, haciendo que si una existía de antes, se eclipse.
>En nuestro lenguaje eso no debería pasar, si existe fuera, entonces no se re-declara si se hacen varias a la vez. Solo cuando se hace una.

## Generics

```
MyGenericType<# t: Type> :: Type = struct [
	datos : List(t)
]
```


> [!TODO] Pensar en la sintaxis de inicialización de instancias de tipos.

>[!BUG] Generics in abstracts
> La sintaxis para conecta qué campo del abstract corresponde con qué campo del hijo no es muy buena.
> Como sabe la funcion canbe lo que hay que saber.


Dilemita con generics:

Since `Point{Float64}` is not a subtype of `Point{Real}`, the following method can't be applied to arguments of type `Point{Float64}`:

```julia
function norm(p::Point{Real})
    sqrt(p.x^2 + p.y^2)
end
```

A correct way to define a method that accepts all arguments of type `Point{T}` where `T` is a subtype of [`Real`](https://docs.julialang.org/en/v1/base/numbers/#Core.Real) is:

```julia
function norm(p::Point{<:Real})
    sqrt(p.x^2 + p.y^2)
end
```

(Equivalently, one could define `function norm(p::Point{T} where T<:Real)` or `function norm(p::Point{T}) where T<:Real`; see [UnionAll Types](https://docs.julialang.org/en/v1/manual/types/#UnionAll-Types).)



Esto para los aliases vendría bien:

Go introdujo la posibilidad de usar `~` (tilde) para indicar subyacencia, o sea `T` puede ser cualquier tipo cuyo subyacente sea `int`, `float64`, etc.

Sobre los generics:
- **Si quieres aprender la “base teórica” de polimorfismo paramétrico**, Haskell es muy instructivo.
- **Si quieres ver un enfoque práctico, moderno, con control de memoria y alta optimización**, Rust es un modelo muy interesante.
- **Si buscas algo minimalista**, Go 1.18+ es el más reciente ejemplo de un diseño de generics intencionalmente reducido, útil para aprender cómo un lenguaje “simple” puede integrar un sistema genérico sin volverse extremadamente complejo.

CONVIVENCIA DE FUNCIONES CON GENERICS:

- Son iguales que los argumentos de funciones, pero Los tipos NO PUEDEN TENER MULTIPLE DISPATCH. 
