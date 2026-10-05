# Serialization foundations

Import `codecs/serialization/json` or `codecs/serialization/csv` by name.
Allocation and I/O capabilities are explicit.

## JSON

`validate` checks one complete UTF-8 JSON value without allocating. The maximum
container depth defaults to 64 and cannot exceed 256. Number syntax is checked
without rounding or range conversion; duplicate object keys remain valid. The
Unicode profile rejects isolated UTF-16 surrogates in escaped strings.

`JsonCursor` validates its input once, then returns borrowed token lexemes.
The input must remain alive and unchanged. A token's `kind` is its first byte;
string lexemes include quotes, and number lexemes preserve their original text.
Call `decode_string` to obtain independent UTF-8 storage, or `write_string` to
emit escaped text. Validation precedes output writes; writer errors may leave a
prefix. Tree construction, typed decoding and full document builders remain
consumer layers above these primitives.

## CSV

`CsvReader` borrows a complete byte string and returns independently owned
`CsvRecord` values. Fields preserve bytes without encoding conversion. Quoted
fields accept embedded line breaks and doubled quotes; record endings accept
CRLF and LF. Bare CR outside quotes, unclosed quotes and trailing bytes after a
closing quote are errors. Empty input contains no records; a blank line contains
one empty field. A trailing comma adds an empty field.

Limits apply to decoded bytes per field and field count per record. Errors are
terminal and destroy partially decoded owners. The caller validates encoding,
column count and field types. `write_record` quotes all supplied fields and
uses CRLF; output failures may leave a prefix. No automatic header detection,
whitespace trimming or comment handling is performed.
