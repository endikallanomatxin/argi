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

