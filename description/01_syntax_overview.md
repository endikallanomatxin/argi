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


On constant structs: When a struct is constant, you are not allowed to:
- Reassign its name
- Reassign its fields
- Create mutable pointers to it
That is enough, because any modification would require a mutable pointer to the
struct.

## Pointers

Para obtener la referencia a una variable (como en c, go, rust...):

```
p = &x
```

Para desreferenciar un puntero:

```
x = p&
```

Su tipo es:

```
p: &Int
```

- No puede ser nulo.
(Si se quiere hacer nulo, usar un nullable: `?&int`. Más adelante hay más sobre
esto.)

- No se puede hacer aritmética con punteros.
Si quieres hacerlo, tienes que convertirlo en un tipo numérico, hacer la
aritmética y luego volverlo a convertir en un puntero. Es suficientemente
incómodo como para no hacerlo sin querer, te obliga a ser explícito para
cagarla.

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
add (.a: Int, .b: Int) -> (.c: Int) := {
    c = a + b
}

divmod (.n:Int, .d:Int) -> (.quot:Int, .rem:Int) := {
    quot = n / d
    rem  = n % d
}
```

When calling functions:

- you can omit the names of the fields when you specify all of them in the correct order.
- output structs with a single field are automatically unpacked (to avoid unnecessary verbosity).

```
result = add(1, 2) + add(3, 4)
```

When a function has multiple fields in the output struct, you get the struct.

```
-- Without unpacking:
r = divmod(7, 3)

-- Para extraer sólo un campo:
quot, _ = divmod(7, 3)
-- o
quot = divmod(7, 3).quot

-- Para extraer ambos:
quot, rem = divmod(7, 3)
```

> [!NOTE] Como diferenciamos entonces entre un struct literal y un list literal?
> Es un collection literal, que se puede _interpretar_ como un list, struct,
> map o choice literal.


Anonymous functions can be defined like here:

```
some_function_that_needs_another_function(
	(.a: Int, .b: Int) -> (.c: Int) := { c = a + b },
	"Some other argument"
)
```


### Pipe operator

The pipe operator calls the right hand side function, substituting the _ symbol
with the full left hand side expression, if it is a function it contains the
return struct without unpacking.

```
my_var | my_func (_, other_arg)         -- Single piped argument
my_var | my_func (_.a, other_arg, _.b)  -- Multiple piped arguments
```

Se puede pasar por referencia sin necesidad de crear las variables intermedias.

```
my_var | my_func (&_, second_arg)
```


## Initialization of types

Builtins initialize to 0 values. (from Odin)

All types have to methods:
- `init` to create an instance of the type.
- `deinit` to destroy the instance of the type.

When you delcare a new instance:

```
my_thing : MyType = "something"
-- or
my_thing : MyType = ("something", 12, true)
```

What it really does is:

```
my_thing : MyType = init("something")
```

The init function is automatically called and resolved with the multiple
dispatch.

On scope exit, `deinit` is automatically called for all types that are not in the result struct.

That way, everything behaves as if it were a stack variable.


## Keeping

If you want to avoid the destruction of a variable, yo can use the `keep` keyword:

```
my_thing := 42
my_pointer := &my_thing
keep my_thing with my_pointer
```

This is a very confortable way of manual memory management. Almost automatic.


## Generics

- Monomorphized at compile time.

- Do not have multiple dispatch.

- Use structs for their arguments.

```
MyGenericType#(.t: Type) : Type = (
	.datos : List<t>
)
```


