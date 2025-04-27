## Types

Checking type:

```
some_variable is Int    -- Abstract types
some_variable is Int32  -- Concrete types
```

>[!BUG]
>Pensar en una sintaxis buena para hacer comprobación y conversión de tipo

Notes:
- NAMING: Variables are snake_case. But they can have utf8 names.
	to insert LaTeX symbols: `\delta` + Tab
	(from julia)
- All initialize to 0 values. (from Odin)
- Si dices que `x: float` y luego dices `x = 1`, sabe que en realidad quieres decir `1.0`. (from Odin)
- `x, y = y, x` se tiene que poder hacer.


> [!TODO]
> Comparación de Int32 con Int8. ¿Implícito? ¿Requiere cast?
> Sub-typing de List<User> vs List<Person> (variancia).

Inline declaration requires commas, but they can be ommited when using new lines.


### Data modelling types

#### Structs

This declares a new struct type:

```
Pokemon : Type = [
	.ID   :: Int64  = 0    -- It allows default values
	.Name :: String = ""
]
```


This declares a new struct (with no named type):

```
data : [
	.ID   :: Int64
	.Name :: String
] = [
	.ID = 0
	.Name = ""
]
```

Or as a shorthand:

```
data := [
	.ID   :: Int64 = 0
	.Name :: String = ""
]
```

##### Protected fields

Es importante proteger algunos campos para conseguir una mejor encapsulación.

Los campos que empiecen por _ serán privados y no podrán ser accedidos desde fuera del package.

Por ejemplo:

```
MyStruct : Type = [
	._x :: Int = 0
]

get_x(s: MyStruct) := Int {
	return s._x
}

set_x(s: MyStruct, x: Int) {
	s._x = x
}
```

También puede ser útil para garantizar que un struct se inicializa correctamente.

```
MyStruct := [
	._x :: Int = 0
	._y :: Int = 0
	._z :: Int = 0
]

init(#t:==MyStruct, x: Int, y: Int, z: Int) : MyStruct {
	return MyStruct(x, y, z)
}
```

We use dynamic dispatch by value (from Haskell) to create the initializer.

Así se hace como si fuera un método estático.

```
MyType|init(_, a, b, c)
```

Si init toma un solo argumento, entonces se puede usar esta otra sintaxis:

```
my_var : MyType = [1, 2, 3]
```

Esto se convierte en:

```
my_var := MyType|init(_, [1, 2, 3])
```

y queda muy limpio.

> Podríamos extenderlo para que valiera también con varios?



> [!IDEA] Struct field types
> Cuando tienes una app web en go por ejemplo, tienes structs para tus models que tienen un montón de campos que más adelante no vas a usar siempre al completo.
> A veces aunque solo tengas que usar el campo del ID pasas el struct entero para al menos mantener la semántica.
> Igual se podría hacer que cuando se define un structu también se definen tipos nuevos.
> 
> Por ejemplo:
>
>	```
>	User := [
>		ID    :: Int64
>		Name  :: String
>	]
>	userIDs : List(User.ID)  -- En lugar de Users, o simplemente Int64
>	```
>
> Con esto ganamos la información semántica de a qué corresponde lo que estamos usando, sin pagar el precio de pasar todo el struct.


#### Choice

```
Direction : Type = [
	..north
	..east
	..south
	..west
]
```

`int(Directions..north) == 1`

```
-- This suffices as a ChoiceLiteral for assignment
..north
```

>[!BUG]
> Pensar en como hacer para que tengan otros tipos. Como una tagged union.

> [!BUG]
> Pensar en como hacer que tenga un valor por defecto. Igual un `=` por delante del campo?


>[!IDEA]
>Pensar en como hacer para que tengan valores concretos. Igual poniendo un ` = ` tras cada campo.

```
HTTPCode : Type = [
	..OK = 200
	..NotFound = 404
	..InternalServerError = 500
]
```


#### Polymorfism. Abstract.

> [!TODO] Decidir nombre
> Estoy entre: `abstract`, `interface`, `protocol`, `trait`

Los abstract types:
- Permiten definir qué funciones deben poder llamarse sobre un tipo.
- Obligan a especificar explícitamente qué tipos implementan el abstract.
- Permiten definir un tipo por defecto, que será el que se inicialice si se usa como tipo al ser declarado.
- NO permiten definir propiedades (Para evitar malas prácticas)
- Se pueden componer.
- Se pueden definir extender fuera de sus módulos de origen.


Así se declara un tipo abstracto:

```
Animal : Abstract = [
	-- Las funciones se definen con la sintaxis de currying.
	speak(_) := String
]

speak(d: Dog) := String {
	return "Woof"
}

-- Requiere manifestación explícita de la implementación.
Animal canbe Dog

-- Permite definir un valor por defecto.
Animal defaultsto Dog
```

```
Addable : Abstract = [
	operator +(_, _) : _
]
```

To use with generics:

```
List<t:Type> : Abstract = [
	operator get[](_, _) := t
	operator set[](_, _, t)
]

List<t> canbe DynamicArray<t>
List<t> canbe StaticArray<t, Any>
```

To compose them:

```
Number : Abstract = [
	Addable
	Substractable
	Multiplicable
	...
	-- You can mix functions and other abstract types here.
]
```


### Basic types

#### Booleans

and, or, not... se escriben como keywords

Literals are:
- `true`
- `false`

#### Numbers

```
Number : Abstract = [
	...
]

Number canbe [
	Int
	Float
]

Number defaultsto Exact
```

- Underscores can be added to numbers for clarity. For example, `1000000` can be tricky to read quickly, while `1_000_000` can be easier.
- Ints can be written in binary, octal, or hexadecimal formats using the `0b`, `0o`, and `0x`prefixes respectively.
- Floats can be written in a scientific notation.
 
>[!BUG] Pensar
> Cuando haces == entre Int64 y Int8, o Int32 y DynamicInt... debería dejarse comparar variables de distintos tipos?


From Julia:

Number  (Abstract Type)
├─ Complex
└─ Real  (Abstract Type)
   ├─ AbstractFloat  (Abstract Type)
   │  ├─ Float16
   │  ├─ Float32
   │  ├─ Float64
   │  └─ BigFloat
   ├─ Integer  (Abstract Type)
   │  ├─ Bool
   │  ├─ Signed  (Abstract Type)
   │  │  ├─ Int8
   │  │  ├─ Int16
   │  │  ├─ Int32
   │  │  ├─ Int64
   │  │  ├─ Int128
   │  │  └─ BigInt
   │  └─ Unsigned  (Abstract Type)
   │     ├─ UInt8
   │     ├─ UInt16
   │     ├─ UInt32
   │     ├─ UInt64
   │     └─ UInt128
   ├─ Rational
   └─ AbstractIrrational  (Abstract Type)
      └─ Irrational

#### Integers

```
Int : Abstract = [
	float(_) : Float
	operator +(_, _) : Int
	operator -(_, _) : Int
	operator *(_, _) : Int
	operator /(_, _) : Int
	operator %(_, _) : Int
	operator ^(_, _) : Int
	...
]

Int canbe [
	-- Automatically changes size according to the value. Never overflows.
	DynamicInt

	-- Fixed size integers. They overflow. No undefined behavior.
	CustomInt(N)
	Int8, Int16, Int32, Int64, Int128
	UInt8, UInt16, UInt32, UInt64, UInt128
]

Int defaultsto DynamicInt
```

>[!TODO] Darle alguna vuelta a como se gestiona el /0.

#### Floats

```
Float : Type : abstract [
	operator +(_, _) : _
	operator -(_, _) : _
	operator *(_, _) : _
	operator /(_, _) : _
	operator ^(_, _) : _
	...
]

Float canbe [Float8, Float16, Float32, Float64, Float128]
Float defaultsto Float32
Number canbe Float
```


#### Alias

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



### Collection types

They are:
- lists
- maps
- sets
- graphs
- queues

They are all structs!! There is no built-in types for them.

What we have is literals for them:

- List literals

```
l := [1, 2, 3]
```

- Map literals

```
m := ["a"=1, "b"=2]
```

These types are only special in the sense that they are the default types infered from their literals.

More info on collection types in `../library/collections/`

The easy default: definition of a heap allocated dynamic array:

```
l := [1, 2, 3]

-- Turns into:

l : DynamicArray<Int> = DynamicArray|init(_, [1, 2, 3])
```

For the low-level-seeking ones: Definition of a stack-allocated array:

```
l : StackArray<Int, 3> = [1, 2, 3]
```

> [!TODO] Pensar una forma de definir longitud de forma automática.
> Igual que haya valores por defecto en un generic?


### Slices

`2..5` y `2.2.10`

> [!TODO] Pensar en otra sintaxis, que el punto se usa para otras cosas.



### Strings

ThePrimeagen dice que go string handling is mid, rust is amazing.

Two literals:

- `'c'` for characters
- `"string"` for strings

Una lista string, se debería poder "ver" como una lista de chars o una lista de bytes. Un char puede ser de múltiples bytes (UTF8)

```
my_string[5]            -- The fifth character
my_string|bytes_get(&_, 4)  -- The fourth byte
```


Declaration:

```
my_str := "this is a string declaration"

my_str := """
	this is a multi-line string declaration
	Openning line is ignored
	The closing quotes serve as the reference for indentation.
	"""

```

_It would be nice to offer a way to have syntax highlighting in the strings (html, sql, ...)._

```
my_query :="""sql
	SELECT * FROM my_table
	"""
```

Several escape sequences are supported:

- `\"` - double quote
- `\\` - backslash
- `\f` - form feed
- `\n` - newline
- `\r` - carriage return
- `\t` - tab
- `\u{xxxxxx}` - unicode codepoint



#### Private vs. Public

Everything is public by default to make it easier for beginners.

To make a variable or function private just use the word: `priv` in front of the definition.

(similar to Odin)

> [!TODO] Repensar esto. no me gusta que sea una keyword. Si es una keyword, que sea coherente con el resto de cosas similares que se puedan hacer.



#### Type Casting

```
x = 5
y = x|float  -- The name has to be the same as the type but all lowercase
```



