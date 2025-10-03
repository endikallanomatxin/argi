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

> [!TODO] Puede pasarse un puntero $& a una función que espera un &?
> Requerimos casteo explícito?


### Read-only vs read-write pointers

There are two types of pointers:
- Read-write pointers: `&T`
- Read-only pointers: `$&T`

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

All types have two methods:
- `init` to create an instance of the type.
- `deinit` to destroy the instance of the type.

When you delcare a new instance:

```
my_thing := MyType("something", 12, true)
```

> [!TODO]
> Think about syntactic sugar to allow:
> ```
> my_list := (1, 2, 3, 4)
> ```
> which should be:
> ```
> my_list := List#(.t: Int32)(1, 2, 3, 4)
> ```

The init function must be declared like this:

```
init (.empty_struct_pointer: $&MyType, arg1: String, arg2: Int, arg3: Bool) -> (.result: MyType) := {
    ...
}
```

If init function is defined it is called. If it doesn't, it creates an empty struct, if possible.

When init is used, the first argument is the mutable pointer to the declared but uninitialized struct.

So:

```
my_thing := MyType("something", 12, true)
```

is really:

```
my_thing : MyType
init ($&my_thing, "something", 12, true)
```

> [!NOTE] init it the only function allowed to receive uninitialized arguments.
>
> El primer parámetro de init puede ser un puntero a memoria reservada pero no inicializada de ese tipo.
> 
> Chequeos estáticos dentro de init:
> - Write-only sobre *out: no se permite leer campos hasta que estén escritos
>   (idealmente, nunca leer el out).
> - Definite initialization: en todas las rutas de éxito, todos los campos han
>   sido escritos.
> - No escape/no alias: el puntero no puede escaparse (no guardarlo en globals,
>   no capturarlo en closures, no pasarlo a hilos).


> Ventaja: implementación y DX sencillas; no necesitas “propagar estados” por todo el programa.

> [!TODO] Think more about defaults in struct declaration/initialization
> Without the init declared, it would create an empty struct.
> Requiring all the field that have no default.

> [!CHECK]
> Habíamos dicho que no se podía usar un struct sin inicializar.
> Permitimos esto solo para este caso? o en general, y nos obligamos a que se
> trackee a través de las funciones si el struct se ha inicializado? O le damos
> un indicador para decirle al compilador que lo estamos haciendo aposta y que
> lo ignore?
> Igual lo mejor es que sea una excepción? Que al final es el init.


If wanted you can return an empty errable:

```
init(out: $&MyType, ...) -> Errable#((), InitError)
```

On scope exit, `deinit` is automatically called for all types that are not in the result struct.
That way, everything behaves as if it were a stack variable.

> [!NOTE]
> Si hay rutas de error/early-return, garantizad que el valor queda en estado
> no-inicializado (no se llamará deinit), o que se limpia parcial antes de
> salir.
> - Solo se invoca deinit en objetos inicializados.
> - Si init falla (devuelve error), no se llama deinit sobre esa ranura.

> [!NOTE] Para usar el stack, hay que inlinear las funciones de init.
> Si quieres que el objeto esté en el stack, el alloca no se puede llamar dentro de una función.
> Por ejemplo, Array tiene esta firma:
> ```
> init#(.t: Type, .n: Int)(.a: &Array#(.t), .source: ListLiteral#(.t)) -> () #inline { ... }
> ```

> [!IDEA]
> Si usamos init para el casting, en realidad queda bastante bien porque si es
> posible se inlinea probablemente.
> Podría hacerse a través del overloading de la funcón de init.
>
> `init(out: $&TargetType, in: SourceType) -> ()`
> Se usaría:
> `new = TargetType(source_value)`

> [!FIX]
> La llamada a las funciones init tiene el mismo nombre que el tipo, eso hace
> que no se pueda referenciar a la función de init por su nombre. No sé si será
> problema.


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


