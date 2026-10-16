## Strings

Two literals:

- `'c'` for a `UnicodeScalar` value
- `"string"` for a valid UTF-8 `StringView` literal

Text exposes distinct units explicitly:

- `string_bytes`: a read-only byte view; the byte-view type itself carries no
  UTF-8 guarantee.
- `codepoints`: Unicode scalar values from already-valid text.
- Grapheme iteration remains unimplemented.

`String` is not directly indexable. Indexing would mix two
distinct questions:

- byte access,
- text-unit access.

```
my_string | bytes_get(.view = &_, .index = 3)  -- Errable containing the fourth byte
codepoints(.text = view(&my_string))  -- Unicode scalar iteration
```


Declaration:

```
my_str := "this is a string declaration"

my_str := """
	this is a multi-line string declaration
	Opening line is ignored
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
- `\u{xxxxxx}` - Unicode scalar value


## Implementation

`String` owns valid UTF-8 text and a trailing NUL. `StringView` borrows valid
UTF-8 text and records its byte length; it need not include a terminator.
Both representations are private. Embedded NULs are valid text.

Arbitrary bytes use `DynamicArray#(UInt8)` or byte array views.
`string_from_bytes(.bytes, .allocator)` validates and copies them, returning
`invalid_utf8` or `out_of_memory` on failure. Later changes to the source bytes
do not affect the resulting text. There is no public unchecked byte-to-text view.
`string_from_c_string` performs the same validation and copy for C input.

`string_bytes(.text)` exposes a read-only byte view. Text mutation invalidates
borrowed views; it cannot grant mutable access to the representation.

Copying a string view copies only the descriptor. It does not imply
ownership of the underlying bytes.

API convention for borrowed text:

- ordinary read-only text APIs should prefer `StringView` by value.
- `&StringView` should be rare; a view is intended to be a small descriptor, so
  passing a reference to the descriptor usually adds aliasing without useful
  ownership information.
- `&String` should be reserved for APIs that need the owning string object, not
  merely some readable text.
- raw `&CChar` is the C-string / low-level interop boundary, not the general
  string-like input type for high-level APIs.

Avoid adding operation implementations only to accept every adjacent representation
(`StringView`, `&StringView`, `&String`, `&CChar`) unless those representations
carry genuinely different semantics. Too many convenience implementations make
multiple dispatch encode API adapter noise instead of domain meaning.

Text algorithms and formatting helpers such as `format` / `format_into`
accept `StringView` for borrowed text. Raw `&CChar` values cross through the
C-string conversion helpers before reaching high-level text APIs.

The display and concatenation entrypoints also accept explicit borrows of
`String`, keeping conversion inside the library: `print(&text)` borrows without
allocating, and `concat("prefix", &text)` returns a fallible owning `String`.
`concat` accepts views by value and owning strings by reference on either side.
These entrypoints share the view-based implementation; they do not require
implicit borrowing or conversions in ordinary call resolution.

`print` is a line-oriented convenience API: `.terminator: StringView` defaults
to `"\n"`. Pass `.terminator = ""` for no suffix or another view for a custom
suffix. Writing the value and terminator preserves the writer's error reasons;
`print` does not request a flush. Use `write(.self = writer, .value = text)` for
exact text output without a terminator, and explicit `flush` when needed.

Text equality follows the same rule: the byte-wise comparison primitive and
`==` / `!=` select Equal evidence on `StringView` values. Callers with owning `String`
or raw `&CChar` values should convert them explicitly instead of relying on
implicit high-level adapters.

Borrowed byte utilities preserve the backing storage lifetime:

- `find(.self, .pattern)` returns a nullable byte index; an empty pattern
  matches at zero. `contains`, `starts_with`, and `ends_with` use the same
  byte comparisons.
- `trim`, `trim_start`, and `trim_end` remove ASCII whitespace only: space
  and bytes 9 through 13. They return borrowed views, preserve interior bytes
  and embedded NULs, and leave non-ASCII whitespace unchanged. Empty results
  need no one-past reference.
- `split(.self, .separator)` returns a fallible `StringSplitIterator` that
  implements the `Iterator` and `Iterable` contracts with `StringView` items. A `for` loop
  copies its current cursor without advancing the original. The iterator
  borrows both text and
  separator; both backing stores must remain live while it is used. Matching
  is byte-wise and non-overlapping. An empty separator is `empty_separator`;
  an empty input produces one empty segment. Leading, consecutive, and
  trailing separators preserve empty segments. Advancing the iterator does
  not invalidate previous segments, which continue to borrow their source.
  Calling `next` after exhaustion aborts.

Owning string allocation always reserves a trailing NUL. Existing constructors,
`copy`, capacity growth, push operations, and concatenation report
`out_of_memory` when the requested byte extent cannot be represented, as well
as when allocation fails. They reject invalid sums before allocating or
modifying the destination. APIs with recorded source lengths also reject before
reading source bytes; the C-string boundary scans for the terminator to obtain
its length. Failed growth preserves the original
string, including its length, capacity, bytes, and trailing NUL. Geometric growth
saturates at the largest capacity that leaves room for the terminator.
The infallible `string_append_byte` and `string_append_bytes` helpers require
sufficient existing capacity and abort before writing if that precondition fails.

`join(.parts, .separator, .allocator)` accepts an `ArrayView#(StringView)`
and produces a new owning `String`. It inserts the separator only between
parts, preserves empty parts and embedded NULs, and accepts an empty separator.
An empty list produces an owning empty string. Parts and separator may overlap;
the output remains valid after their backing storage ends. The operation checks
the complete byte length, including space for the trailing NUL, before reserving
memory. It makes one allocation and reports `size_overflow` or `out_of_memory`
without publishing a partial string.

`replace(.self, .pattern, .replacement, .allocator)` produces a new owning
`String`, replacing every non-overlapping byte match from left to right.
Replacement bytes are copied without being searched again. Empty replacement
removes matches; no matches produces an independent copy. Empty input remains
empty. An empty pattern reports `empty_pattern` before allocation. Input,
pattern, and replacement may overlap, and the output does not borrow them.
Like `join`, it checks the complete resulting length, reserves the trailing NUL,
makes one allocation, and reports `size_overflow` or `out_of_memory` without
publishing a partial string. These operations do not interpret Unicode or
normalize text.

Nomenclature to keep consistent:

- `bytes`: byte-level access without Unicode interpretation.
- `codepoints`: decoded Unicode scalar values.
- `graphemes`: user-perceived text units, potentially spanning multiple code
  points.

The text model uses these conventions:

- `String` is an owning byte buffer over `Allocation`.
- `String` is also the single growable text buffer shape in `core`; there is
  no separate `TextBuffer` type.
- buffered I/O wrappers borrow their underlying streams and caller-provided
  initialized byte buffers. Both take `.base` and
  `.buffer: MutableArrayView#(UInt8)` and construct without allocation or failure.
  Omitting `.buffer` creates an independent, zero-initialized 4096-byte buffer
  in the caller scope, just like writing the default expression explicitly.
  The adapter cannot outlive that storage.
  Empty buffers delegate directly to the base stream. The caller keeps the
  storage live; neither wrapper frees it. `BufferedWriter` flushes best-effort
  during cleanup; explicit flushing reports errors. `BufferedReader` needs no
  cleanup and never closes its base.
- `read_line()` returns an owning `String`, so the resulting text outlives the
  temporary buffering used while reading.
- string literals materialize as borrowed read-only `StringView`.
- raw `&CChar` stays as the explicit C-string boundary, reached through helpers
  such as `as_c_string(...)` / `string_from_c_string(...)` instead of being the default
  language-level type of `"..."`.
- `String(.length = n)` returns the result of allocating `n` zero bytes plus a trailing NUL.
- `deinit(.self = $&string)` releases the backing allocation.
- `copy(.self = &string, .allocator = allocator)` allocates a second backing
  buffer and copies the bytes, so value semantics stay independent.
- `String` itself is not directly indexable.
- byte-level access is explicit:
  - `bytes_get(.view = &string, .index = i)` returns
    `Errable#(UInt8, (..out_of_bounds))`. Valid indices are strictly below
    `byte_length`; the trailing NUL is accessible only through C interop.
    The same rule applies to `StringView`, including empty views.
  - `string_byte_reference` and `string_view_byte_address` return checked
    `Errable#(&UInt8, (..out_of_bounds))` references within that same range.
  - `set_ascii(.self = $&string, .index = i, .byte = b)` checks the index and
    requires both the old and new byte to be ASCII.
  - `push_ascii`, `push_scalar`, and `push_view` append ASCII, a Unicode scalar,
    or validated text. `push_ascii` rejects a non-ASCII byte with
    `invalid_codepoint` before allocation or mutation. Arbitrary byte input must
    use checked decoding instead.
- `slice(.self = view(&string), .start = start, .count = count)` returns a
  checked borrowed text range; both ends must be UTF-8 scalar boundaries.
- `codepoints(.text = view(&string))` returns a borrowed `CodepointView`
  for scalar iteration without validation or allocation. `utf8_decode` supports
  checked byte offsets.

> [!IMPLEMENTATION]
> Codepoint-range slicing and grapheme views are not implemented. Byte slicing,
> UTF-8 decoding, and validated scalar iteration are available.


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

## Floating-point parsing

`parse_float16`, `parse_float32`, and `parse_float64` accept `.text: StringView`
and return an `Errable` containing the named target type. Parsing consumes
exactly the recorded byte extent, uses no allocator, and is independent of
locale. Supported input is ASCII decimal notation: an optional leading sign,
at least one digit before or after an optional decimal point, and an optional
`e` or `E` exponent with an optional sign and at least one digit. Examples
include `12`, `-0.5`, `.5`, `5.`, and `+3.25e-2`.

Whitespace, separators, radix prefixes, embedded zero bytes, trailing bytes,
and special spellings such as `nan` and `inf` produce `invalid_input`. The
complete input grammar is checked before determining range, so a malformed
suffix remains `invalid_input` even after an enormous exponent.

Valid decimal inputs round directly to the target's IEEE binary format using
round-to-nearest, ties-to-even. Finite subnormal results are accepted. A
nonzero input that rounds to zero or infinity produces `out_of_range`;
representable rounded finite values are accepted even when the exact input
is slightly outside their range. Exact zero accepts any exponent and preserves
its sign, including negative zero. The decimal-to-binary conversion never
passes through a wider floating-point type, avoiding double rounding.

## Integer formatting

`format(.value: T, .allocator: $&Allocator)` returns an owning `String` for
`Int8`, `Int16`, `Int32`, `Int64`, `UInt8`, `UInt16`, `UInt32`, `UInt64`, and
`UIntNative`. Decimal output uses ASCII digits, no separators, and a leading
minus sign only for negative values. Zero is `"0"`; signed minima and unsigned
maxima retain their full range. The result uses one allocation sized for the
text and its zero terminator.

`format_into(.out: $&String, .value: T, .allocator: $&Allocator)` appends the
same representation. Decimal conversion uses fixed local storage; only growth
of the destination string can allocate. A failed reservation leaves the
existing string unchanged. String formatting returns `out_of_memory` on an
allocation failure.

`WriteValue#(Stream, T).write_value(.self: $&Stream, .value: T)` sends the same decimal bytes to a writer
without an allocator or an intermediate owning string. Participants are explicit
in qualified calls; generic callers retain their stream and value type parameters.
The contract permits specialization for a concrete stream/value pair.
`print(.value: T,
.writer: $&Writer, .terminator: StringView = "\n")` adds the usual terminator;
a locally assumed writer can satisfy its writer input. These operations
preserve `stream_write_failed` and `stream_flush_failed`, stop at the first
failed byte, and leave the successfully written prefix in the destination.
A value failure prevents writing the terminator. They request no implicit
flush; a writer may flush internally while accepting bytes.

## Floating-point formatting

The same string `format` / `format_into`, stream `WriteValue.write_value`, and
`print` inputs accept `Float16`,
`Float32`, and `Float64`. Each finite value uses the shortest decimal
significand that reads back as exactly that value at its original width under
round-to-nearest, ties-to-even. Among equally short candidates, formatting
chooses the closest decimal value; an exact tie chooses an even decimal
significand. Formatting does not widen the float before choosing its text.

All widths use fixed notation when the decimal exponent of the leading digit
is between -4 and 15, inclusive, and scientific notation otherwise. Fixed
integral values retain `.0`. Scientific notation uses a lowercase `e`, no
positive exponent sign, and no exponent padding. Examples include `0.1`,
`1.0`, `0.0001`, `1e-5`, and `1e16`. Zero preserves its sign as `0.0` or
`-0.0`. Positive and negative infinity use `inf` and `-inf`; every NaN uses
`nan`, without preserving its sign or payload. The finite decimal parser
continues to reject these special-value spellings.

Formatting uses bounded local storage, independent of locale and the host C
library. Writer formatting needs no allocator, requests no implicit flush,
and follows the integer formatter's prefix and error propagation contract.
An owning string requires one allocation for the resulting bytes and their
zero terminator; appending to a string allocates only when its capacity grows.

## Strict UTF-8 operations

`String` and `StringView` guarantee valid UTF-8. Byte decoding is explicit and
accepts bounded byte views, including embedded NULs.

`UnicodeScalar(.value: UInt32)` checks the Unicode scalar range: zero through
U+10FFFF, excluding U+D800 through U+DFFF. Invalid input reports
`invalid_codepoint`; `scalar_value(.self)` returns the checked UInt32 value.
The scalar representation is private and implicitly copyable.

`utf8_decode(.text, .offset = 0)` returns `Utf8Decoded` with `.scalar` and the
consumed `.width` in bytes. An offset at or beyond the end reports
`out_of_bounds`. An offset inside a multibyte scalar reports `invalid_utf8`,
even though the complete text is valid.

`validate_utf8_bytes(.bytes)` checks arbitrary bytes and returns their scalar
count. `utf8_decode_bytes(.bytes, .offset)` decodes one scalar. Invalid leading
or continuation bytes, truncated sequences, overlong encodings, surrogate
encodings, and values above U+10FFFF report `invalid_utf8`. Decoding does not
replace invalid bytes or skip them.
For valid text, `length(&codepoints(.text = text))` counts its scalars.
Empty text is valid and has count zero. `utf8_encoded_length(.scalar)` returns
one through four. `utf8_encode(.scalar, .buffer, .offset = 0)` writes the shortest
UTF-8 encoding to initialized mutable byte storage and returns its width. It
checks the whole destination first; `out_of_bounds` leaves every byte unchanged,
including for oversized offsets. These operations allocate no storage.

`Utf8Decoder(.text)` or `Utf8Decoder(.bytes)` starts at offset zero.
`next_codepoint(.self)` returns an errable optional scalar: none at end,
`invalid_utf8` on malformed input, or a scalar and an advanced byte position on
success. `position(.self)` reports that byte position. Failure preserves the
position; end remains stable. This checked cursor can handle unvalidated input
without pretending that fallible decoding is an infallible iterator operation.

`CodepointView(.text)` or `codepoints(.text)` returns a borrowed, implicitly
copyable scalar view of an already-valid `StringView`. Construction is
infallible, constant-time, and allocates no storage. `length(.self)` scans the
text to count scalars; it does not cache a count. `view(&view)` retrieves the
original `StringView`. `for scalar in view` decodes `UnicodeScalar` values as
it advances, without a preliminary scan. `CodepointIterator` retains backing
storage lifetimes; copied scalars are independent values. `next` requires a
successful `has_next` and aborts at end. Arbitrary byte input uses the fallible
`Utf8Decoder` or `utf8_decode_bytes` APIs instead.

Text views preserve their validity through storage dependencies: mutating the
owning string invalidates existing views. Checked byte decoders do not certify
or freeze their source. UTF-8 decoding performs no normalization, case folding,
grapheme segmentation, or display-width calculation; a scalar count is not a
count of user-perceived characters.

`parse_uintnative(.text, .base = 10)` reads an unsigned integer using the
compilation target's pointer width. It has the same digit and error contracts
as the fixed-width integer parsers; out-of-range values never truncate.

ASCII byte helpers classify ASCII, digits, lower/upper letters, letters,
alphanumeric bytes and whitespace through `ascii_is_ascii`, `ascii_is_digit`,
`ascii_is_lower`, `ascii_is_upper`, `ascii_is_alpha`, `ascii_is_alphanumeric`
and `ascii_is_whitespace`. Whitespace includes space and bytes 9 through 13.
`ascii_to_lower` and `ascii_to_upper` preserve nonletters and non-ASCII bytes;
they do not perform Unicode case folding. Trimming uses the same whitespace
classification. `find_last(.self, .pattern)` returns the last matching byte
offset; the empty pattern matches at the end of the view.

`split_whitespace(.self)` returns a borrowed `StringWhitespaceIterator`.
Use `has_next` and `next` to consume nonempty tokens separated by ASCII
whitespace. Leading, repeated and trailing whitespace is skipped. Empty or
all-whitespace input has no tokens. Returned tokens retain their source
lifetime and remain valid when the iterator advances. Unicode whitespace is
not a separator; UTF-8 bytes and embedded NULs otherwise remain unchanged.

`slice(.self: StringView, .start, .count)` checks byte ranges and returns an
`Errable` view with `out_of_bounds` for invalid ranges and
`invalid_utf8_boundary` when either end splits a scalar. Empty slices at the extent succeed without
forming a one-past reference. Oversized counts and offsets cannot wrap.

Whitespace iterators also support `for token in split_whitespace(.self = text)`.
Iteration copies the remaining cursor state; it does not advance the original
iterator. The copy retains the same source lifetime.

`capacity(&string).count` reports the usable byte capacity, excluding the trailing
NUL. ASCII edits report `invalid_codepoint` without changing the text when the
input byte is not ASCII. `set_ascii` also rejects replacing any byte of a
multibyte scalar. `append_ascii_assume_capacity` performs the same ASCII check
but requires sufficient capacity; its name makes that storage precondition
explicit. `append_text_assume_capacity` accepts already-valid text and likewise
requires sufficient capacity.
