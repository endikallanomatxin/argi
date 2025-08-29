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
l := (1, 2, 3)
```

- Map literals

```
m := ("a"=1, "b"=2)
```

These types are only special in the sense that they are the default types infered from their literals.

More info on collection types in `../library/collections/`

The easy default: definition of a heap allocated dynamic array:

```
l := (1, 2, 3)

-- Turns into:

l : DynamicArray#(Int) = DynamicArray|init(_, (1, 2, 3))
```

For the low-level-seeking ones: Definition of a stack-allocated array:

```
l : StackArray#(Int, 3) = (1, 2, 3)
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
my_string(5)            -- The fifth character
my_string | bytes_get(&_, 4)  -- The fourth byte
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

- `\"` - double quote
- `\\` - backslash
- `\f` - form feed
- `\n` - newline
- `\r` - carriage return
- `\t` - tab
- `\u{xxxxxx}` - unicode codepoint


