## Strings

ThePrimeagen says Go's string handling is mediocre, while Rust's is amazing.

Two literals:

- `'c'` for characters
- `"string"` for strings

A string should be explicitly viewable in several forms:

- `bytes`: the raw UTF-8 bytes.
- `codepoints`: Unicode scalar values decoded from those bytes.
- `graphemes`: visual units perceived by the user.

`String` should not be directly indexable by default. This mixes two
preguntas distintas:

- byte access,
- text-unit access.

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

API convention for borrowed text:

- ordinary read-only text APIs should prefer `StringView` by value.
- `&StringView` should be rare; a view is intended to be a small descriptor, so
  passing a reference to the descriptor usually adds aliasing without useful
  ownership information.
- `&String` should be reserved for APIs that need the owning string object, not
  merely some readable text.
- raw `&Char` is the C-string / low-level interop boundary, not the general
  string-like input type for high-level APIs.

Avoid adding overloads only to accept every adjacent representation
(`StringView`, `&StringView`, `&String`, `&Char`) unless those representations
carry genuinely different semantics. Too many convenience overloads make
multiple dispatch encode API adapter noise instead of domain meaning.

For example, terminal text helpers such as `print` / `print_error` and
formatting helpers such as `format` / `format_into` accept `StringView` for
text. Callers with an owning `String` should call `as_view(...)` explicitly, and
raw `&Char` values should cross through the C-string conversion helpers before
reaching high-level text APIs.

Text equality follows the same rule: the byte-wise comparison primitive and
`==` / `!=` overloads work on `StringView` values. Callers with owning `String`
or raw `&Char` values should convert them explicitly instead of relying on
high-level adapter overloads.

Nomenclature to keep consistent:

- `bytes`: byte-level access over UTF-8 storage.
- `codepoints`: decoded Unicode scalar values.
- `graphemes`: user-perceived text units, potentially spanning multiple code
  points.

The text model uses these conventions:

- `String` is an owning byte buffer over `Allocation`.
- `String` is also the single growable text buffer shape in `core`; there is
  no separate `TextBuffer` type.
- buffered IO wrappers own only their internal byte buffers; they borrow the
  underlying stream handles.
- `read_line()` returns an owning `String`, so the resulting text outlives the
  temporary buffering used while reading.
- string literals materialize as borrowed read-only `StringView`.
- raw `&Char` stays as the explicit C-string boundary, reached through helpers
  such as `as_c_string(...)` / `as_view(...)` instead of being the default
  language-level type of `"..."`.
- `init(.p = $&string, .length = n)` allocates exactly `n` bytes.
- `deinit(.self = $&string)` releases the backing allocation.
- `copy(.self = string)` allocates a second backing buffer and copies the
  bytes, so value semantics stay independent.
- `String` itself is not directly indexable.
- byte-level access is explicit:
  - `bytes_get(.string = &string, .index = i)`
  - `bytes_set(.string = $&string, .index = i, .value = b)`
- byte/code-point/grapheme slicing uses explicit view
  constructors such as:
  - `view_bytes(.string = &string, .from = from, .to = to)`
  - `view_codepoints(.string = &string, .from = from, .to = to)`
  - `view_graphemes(.string = &string, .from = from, .to = to)`
- text-level indexing belongs on those views, not directly on
  `String`.
- borrowed `StringViewRO/RW` types provide
  explicit windows into a string, but byte indexing should not live directly on
  `String`.

> [!IMPLEMENTATION]
> UTF-8-aware indexing and the view constructors described above are not yet
> available. The owner/view split already exists.


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
> This could be done by connecting to the active LSP.

## Byte search

`find(.self: StringView, .pattern: StringView)` returns the first matching
byte offset as `?UIntNative`, or `none` when the pattern does not occur.
`contains`, `starts_with`, and `ends_with` return an `ok` boolean. These
operations compare bytes, include embedded zero bytes, and allocate no storage.
An empty pattern matches at offset zero and is both a prefix and a suffix,
including for an empty input. A pattern longer than the input does not match.
Offsets count bytes rather than Unicode code points or graphemes.

## Integer parsing

`parse_int8`, `parse_int16`, `parse_int32`, and `parse_int64`, and their
`parse_uint8`/`16`/`32`/`64` counterparts, accept `.text: StringView` and
`.base: UInt8 = 10`. Each returns an `Errable` containing the named target type.
Parsing is allocation-free and accepts exactly the recorded byte extent.

Bases range from 2 through 36. Digits are ASCII `0`–`9` and `a`–`z`, with
uppercase letters accepted equally. An optional leading `+` is accepted for
all targets; `-` is accepted only for signed targets, including signed zero.
At least one digit is required. Whitespace, separators, embedded zero bytes,
and radix prefixes such as `0x` are rejected; callers pass the base explicitly.

Errors distinguish `invalid_base`, `invalid_input`, and `out_of_range`.
The base is checked first; input bytes are then checked from left to right,
returning the first encountered invalid digit or range failure. Every
multiply/add or subtract is checked against the target range before execution.
Signed minima and the full unsigned maximum are representable without first
converting their magnitude to a signed intermediate.
