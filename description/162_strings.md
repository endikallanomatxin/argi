## Strings

ThePrimeagen dice que go string handling is mid, rust is amazing.

Two literals:

- `'c'` for characters
- `"string"` for strings

Un string se debería poder "ver" de varias formas explícitas:

- `bytes`: los bytes UTF-8 crudos.
- `codepoints`: valores Unicode escalares decodificados desde esos bytes.
- `graphemes`: unidades visuales percibidas por el usuario.

`String` no debería ser indexable directamente por defecto. Eso mezcla dos
preguntas distintas:

- acceso por byte,
- acceso por unidad de texto.

```
my_string | bytes_get(&_, 4)  -- The fourth byte
my_string | view_codepoints(&_, 0, 5) | _[4]  -- Future explicit code-point view
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

Strings should follow the same ownership split as lists:

- `String` is the owning type.
- it should be backed by `Allocation`.
- string views should stay borrowed and non-owning.

One reasonable base direction is:

```
String : Type = (
    .allocation : Allocation
    .length     : UIntNative
)

StringViewRO : Type = (
    .string : &String
    .start  : UIntNative
    .length : UIntNative
)

StringViewRW : Type = (
    .string : $&String
    .start  : UIntNative
    .length : UIntNative
)
```

Copying a string view should copy only the descriptor. It should never imply
ownership of the underlying bytes.

Nomenclature to keep consistent:

- `bytes`: byte-level access over UTF-8 storage.
- `codepoints`: decoded Unicode scalar values.
- `graphemes`: user-perceived text units, potentially spanning multiple code
  points.

Current implementation direction:

- `String` is now an owning byte buffer over `Allocation`.
- `init(.p = $&string, .length = n)` allocates exactly `n` bytes.
- `deinit(.self = $&string)` releases the backing allocation.
- `copy(.self = string)` allocates a second backing buffer and copies the
  bytes, so value semantics stay independent.
- `String` itself is not directly indexable for now.
- byte-level access is explicit:
  - `bytes_get(.string = &string, .index = i)`
  - `bytes_set(.string = $&string, .index = i, .value = b)`
- future byte/code-point/grapheme slicing should happen through explicit view
  constructors such as:
  - `view_bytes(.string = &string, .from = from, .to = to)`
  - `view_codepoints(.string = &string, .from = from, .to = to)`
  - `view_graphemes(.string = &string, .from = from, .to = to)`
- future text-level indexing should happen on those views, not directly on
  `String`.
- borrowed `StringViewRO/RW` types still make sense as the longer-term shape for
  explicit windows into a string, but byte indexing should not live directly on
  `String`.

This is intentionally narrower than the long-term text model. UTF-8-aware
character indexing and higher-level string construction can be layered on top
later, but the base owner/view split should already be real and usable.


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
