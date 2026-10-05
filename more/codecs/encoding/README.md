# Byte-to-text encodings

`codecs/encoding/hex` encodes lowercase hexadecimal and decodes either case.
Decoding requires an even number of digits and accepts no whitespace.

`codecs/encoding/base64` uses the standard RFC 4648 alphabet and required
padding. Decoding rejects whitespace, misplaced padding, invalid symbols and
nonzero unused bits in the final group. URL-safe alphabets and unpadded forms
require separate policies.

Both modules validate before allocating decoded output. Encoded strings and
decoded byte arrays own independent storage, retain their allocator's lifetime,
and preserve embedded zero bytes. Capacity arithmetic is checked before writing.
