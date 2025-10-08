## Strings

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



Several escape sequences are supported:

- `\"` - double quote
- `\\` - backslash
- `\f` - form feed
- `\n` - newline
- `\r` - carriage return
- `\t` - tab
- `\u{xxxxxx}` - unicode codepoint


## Implementation

Similar to lists

```
String#(
    .b: Int32      -- bytes
    .nsbc: Int32   -- non-single-byte characters
) : Type = (

    .data   : [b]Uint8
    .length : Int32

    .nsbc_indeces            : [nsbc]Int32
    .extra_bytes_accumulated : [nsbc]Int32
    -- searching in nsbc_indeeces is done with binary search O(log nsbc)
    -- then finding the exact byte index is almost instantáneous O(1)
)

DynamicString : Type = (
    .data                    : DynamicArray#(Uint8)
    .nsbc_indeces            : DynamicArray#(Int32)
    .extra_bytes_accumulated : DynamicArray#(Int32)
)

StringView : Type = (
    .data : &String
    .start: Int32
)
```

When a constant string is defined: String
When a variable string is defined: DynamicString


> [!IDEA]
> _It would be nice to offer a way to have syntax highlighting in the strings (html, sql, ...)._
> 
> ```
> my_query :="SELECT * FROM my_table"sql
> 
> my_html := """html
> 	<div>
> 		<p>Hello, world!</p>
> 	</div>
> 	"""
> ```
> Podría hacerse conectándose al lsp de turno.

