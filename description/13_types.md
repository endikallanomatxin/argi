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


Inline declaration requires commas, but they can be ommited when using new lines.


### Data modelling types

#### Structs

This declares a new struct type:

```
Pokemon :: Type = [
	.ID   : Int64  = 0    -- It allows default values
	.Name : String = ""
]
```


This declares a new struct (with no named type):

```
data :: [
	.ID   : Int64
	.Name : String
] = [
	.ID = 0
	.Name = ""
]
```

Or as a shorthand:

```
data ::= [
	.ID   : Int64 = 0
	.Name : String = ""
]
```

##### Protected fields

Es importante proteger algunos campos para conseguir una mejor encapsulación.

Los campos que empiecen por _ serán privados y no podrán ser accedidos desde fuera del package.

Por ejemplo:

```
MyStruct :: Type = [
	._x : Int = 0
]

get_x(s:: MyStruct) ::= Int {
	return s._x
}

set_x(s:: MyStruct, x:: Int) {
	s._x = x
}
```

También puede ser útil para garantizar que un struct se inicializa correctamente.

```
MyStruct ::= [
	._x : Int = 0
	._y : Int = 0
	._z : Int = 0
]

init(x: Int, y: Int, z: Int) :: MyStruct {
	return MyStruct(x, y, z)
}
```


>[!BUG] Sintaxis inicialización de tipo
>
> >[!IDEA] Dispatch by value
> >
> > Para inicializar:
> >	```
> >	init(#t :: Type == MyType, a: Int, b: Int, c: Int) :: MyType { ... }
> >	```
> > Así se hace como si fuera un método estático.
> >	```
> >	MyType|init(a, b, c)
> >	```
> > Es un poco como en haskell, que se puede hacer dispatch en función no solo del tipo del input, sino también del valor. En algunos casos igual queda limpio.
> >
> >	```haskell
> >	factorial 0 = 1
> >	factorial n = n * factorial (n-1)
> >	```
> > sería
> >	```
> >	factorial(n:: Int == 0) :: Int { 1 }
> >	factorial(n:: Int) :: Int { n * factorial(n-1) }
> >	```
> > Si vamos a permitir el multiple dispatch por valor, es una buena forma de hacerlo. Lo único que igual añade demasiada complejidad.
>
> 
> >[!IDEA] Inferencia de tipo de retorno
> >	```
> >	-- Igual init que devuelva MiTipo? Es capaz de inferir eso?
> >	-- O igual eso obliga a que se rutee el dispatch también en función del return type? Eso no está bien.
> >	
> >	x :: MiTipo = init([1, 2, 3])
> >	
> >	init(list::List<Any>) :: MiTipo {
> >		...
> >	}
> >	```
> 
> Si no, siempre se puede hacer con funciones init_TypeName().


> [!IDEA] Struct field types
> Cuando tienes una app web en go por ejemplo, tienes structs para tus models que tienen un montón de campos que más adelante no vas a usar siempre al completo.
> A veces aunque solo tengas que usar el campo del ID pasas el struct entero para al menos mantener la semántica.
> Igual se podría hacer que cuando se define un structu también se definen tipos nuevos.
> 
> Por ejemplo:
>
>	```
>	User ::= [
>		ID    : Int64
>		Name  : String
>	]
>	userIDs : List(User.ID)  -- En lugar de Users, o simplemente Int64
>	```
>
> Con esto ganamos la información semántica de a qué corresponde lo que estamos usando, sin pagar el precio de pasar todo el struct.


#### Choice

```
Direction :: Type = choice [
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

>[!IDEA]
>Pensar en como hacer para que tengan valores concretos. Igual poniendo un ` = ` tras cada campo.


#### Polymorfism. Abstract.

Un abstract es como una interfaz en go, solo qué:
- también permite definir atributos (si es que se trata de un struct)
- Hay que decir cuando un tipo implementa una interface.
- Se le puede poner un tipo por defecto.

Es importante que el canbe pueda ser definido a posteriori y fuera del paquete, para que tenga la flexibilidad de Julia.

```
Animal :: Abstract = [
	.name : String
	speak(_) => String
	do_something(_, Int)
]

Dog :: Type = struct [
	.name : String
	.breed : String
]

speak(d: Dog) ::= String {
	return "Woof"
}

Animal canbe Dog

Animal defaultsto Dog
```

### Basic types

#### Booleans

and, or, not... se escriben como keywords

Literals are:
- `true`
- `false`

#### Numbers

```
Number :: Abstract = [
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

#### Integers

```
Int :: Abstract = [
	float(_) :: Float
	operator +(_, _) :: Int
	operator -(_, _) :: Int
	operator *(_, _) :: Int
	operator /(_, _) :: Int
	operator %(_, _) :: Int
	operator ^(_, _) :: Int
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
	operator +(_, _) :: _
	operator -(_, _) :: _
	operator *(_, _) :: _
	operator /(_, _) :: _
	operator ^(_, _) :: _
	...
]

Float canbe [Float8, Float16, Float32, Float64, Float128]
Float defaultsto Float32
Number canbe Float
```


#### Alias

Se hace con la misma sintaxis que para la definición de tipos.

```
Name :: Type = String  -- Uff pero esto es el abstract o el tipo.
```

Los aliases son inputs válidos para funciones con input del tipo subyacente.


### Collection types

They are:
- lists
- maps
- sets

They are all structs!! There is no built-in types for them.

What we have is literals for them:

- List literals

```
l ::= [1, 2, 3]
```

- Map literals

```
m ::= ["a"=1, "b"=2]
```

These types are only special in the sense that they are the default types infered from their literals.

##### Lists

```
Index :: Type = Int64  -- 1 based index

List<t> :: Abstract = [
	.type : Type

	append(_, _.type)
	insert(_, _.type, Index)
	remove(_, Index)
	length() :: Int
	...
]

List<t> canbe [
	Array<t, _>     -- Static length
	DynamicArray<t> -- Dynamic length thanks to buffer
	Chain<t>        -- Linked list ( one-directional or two directional ? )
	Rope<t>         -- es una linked list de arrays, representada en un BTree
]

List defaultsto DynamicArray
```

>[!BUG] Generics in abstracts
> La sintaxis para conecta qué campo del abstract corresponde con qué campo del hijo no es muy buena.
> Como sabe la funcion canbe lo que hay que saber.

Definition of a dynamic array:

```
l := [1, 2, 3]

-- Turns into:

l : DynamicArray<Int> = DynamicArray|init([1, 2, 3])

```

Definition of a static array:

```
l : Array<Int, 3> = [1, 2, 3]

-- Turns into

l : Array<Int, 3> = Array|init(Int, 3, [1, 2, 3])
```


>[!IDEA] Sintaxis para una lista dinámica literal
>```
>[1, 2, 3, ...]
>```
> Eso se convierte en una DynamicList y si no pones ... entonces se convierte en Array


** AoS to SoA **

_Igual es buena idea una forma fácil de que un array de structs internamente se implemente como un struct de arrays. O hacer una forma fácil de convertir de uno a otro._

Esto es útil porque hace que se almacenen los datos con menos padding.

Igual puede hacerse como
- conversión como método de listas de structs para convertir en struct de listas: |aos_to_soa()
- implementación interna, pero uso del usuario sin modificar: |optimize_internal_layout_as_soa()

##### Maps

Value puede o no ser heterogéneo (`Any`). El key no puede nunca ser heterogéneo. 
_(Esto es una limitación artificial para evitar código mierdoso. En go por ejemplo no se puede y no entiendo en qué contexto podría ser útil. Mejor evitarlo.)_
Si se pone un abstract con default, entonces se tomará como el tipo del key.

```
-- Un típico dict
notas : Map<String, Int> = [
	"Mikel"=8
	"Jon"=9
]
```

Por defecto si haces:
```
notas := ["Mikel"=8, "Jon"=9]
```
infiere los tipos.


##### Sets

an unordered collection of unique items.

```plaintext
m : Set<Int> = [1, 2, 3]
```

Como usa un list literal, siempre hay que especificar el tipo.



##### Slices

`2..5` y `2.2.10`


##### Strings

ThePrimeagen dice que go string handling is mid, rust is amazing.

Two literals:

- `'...'` for characters
- `"..."` for strings

Una lista string, se debería poder "ver" como una lista de chars o una lista de bytes. Un char puede ser de múltiples bytes (UTF8)

```
my_string.chars[5]
my_string.bytes[4]
```

```
String :: Abstract = [
	char_length(_) :: Int
	byte_length(_) :: Int
]

String canbe [
	DynamicString
	ArrayString
	LinkedListString
	RopeString
	NullTerminatedString -- For C interop
]

String defaultsto DynamicString
```

```
LengthedString :: Type = struct [
    content :: &char
    length  :: int64
]
```

```
DynamicString :: Type = struct [
    buffer   : Array(Byte)
    length   : Int         -- Longitud actual
    capacity : Int         -- Máxima longitud
]
```


Declaration:

```
my_str :: String = "this is a string declaration"

my_str ::= """
	this is a multi-line string declaration
	Openning line is ignored
	The closing quotes serve as the reference for indentation.
	"""

```

_It would be nice to offer a way to have syntax highlighting in the strings (html, sql, ...)._

```
my_query ::="""sql
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

##### Graphs

Tree
Btree


##### Queues

Stack
Queue
PriorityQueue (implemented as a FibonacciHeap)


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



