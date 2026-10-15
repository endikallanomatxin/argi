-- Scalars exclude surrogate code points and fit the Unicode codespace.
UnicodeScalar: Type = (._value: UInt32)

implement ImplicitlyCopyable#(UnicodeScalar) ()

implement Init#(
    UnicodeScalar,
    (
        .value : UInt32,
    )
) (
        .Result : Type = Errable#(UnicodeScalar, (..invalid_codepoint))
        .init   = (
                .args : (
                    .value : UInt32,
                )
            ) -> (
                .result : Result
            ) {
            value ::= args.value

            if value > 1114111 or [value >= 55296 and value <= 57343] {
                result = ..error(.reason = ..invalid_codepoint)
                return
            }

            result = ..ok(._value = value)
        }
    )

scalar_value(.self: UnicodeScalar) -> (.value: UInt32) := { value = self._value }

Utf8Decoded: Type = (.scalar: UnicodeScalar, .width: UIntNative)

implement ImplicitlyCopyable#(Utf8Decoded) ()

_Utf8Decode: Type = (..valid(.decoded: Utf8Decoded), ..invalid, ..outside)

implement ImplicitlyCopyable#(_Utf8Decode) ()

-- Keep the proven decoder infallible so validated iteration has no error-tracer
-- dependency. Public operations translate these outcomes into their Errable contract.
_utf8_decode(.text: StringView, .offset: UIntNative) -> (.result: _Utf8Decode) := {
    if offset >= text.length {
        result = ..outside
        return
    }

    first ::= bytes_get(.view = &text, .index = offset).byte
    code :: UInt32 = 0
    width :: UIntNative = 0
    minimum :: UInt32 = 0

    if first < 128 {
        width = 1
        code = first | convert#(.to: UInt32)(_)
    }

    if first >= 194 and first <= 223 {
        width = 2
        minimum = 128
        code = [first - 192] | convert#(.to: UInt32)(_)
    }

    if first >= 224 and first <= 239 {
        width = 3
        minimum = 2048
        code = [first - 224] | convert#(.to: UInt32)(_)
    }

    if first >= 240 and first <= 244 {
        width = 4
        minimum = 65536
        code = [first - 240] | convert#(.to: UInt32)(_)
    }

    if width == 0 {
        result = ..invalid
        return
    }

    if width > text.length - offset {
        result = ..invalid
        return
    }

    index :: UIntNative = 1

    while index < width {
        byte ::= bytes_get(.view = &text, .index = offset + index).byte
        if byte < 128 or byte > 191 {
            result = ..invalid
            return
        }
        code = code * 64 + [byte - 128] | convert#(.to: UInt32)(_)
        index = index + 1
    }

    if code < minimum or code > 1114111 or [code >= 55296 and code <= 57343] {
        result = ..invalid
        return
    }

    result = ..valid(.decoded = (.scalar = (._value = code), .width = width))
}

utf8_decode(
        .text   : StringView,
        .offset : UIntNative  = 0
    ) -> (
        .result : Errable#(Utf8Decoded, (..invalid_utf8, ..out_of_bounds))
    ) := {
    match _utf8_decode(.text = text, .offset = offset).result {
        ..valid payload { result = ..ok payload.decoded }
        ..invalid { result = ..error(.reason = ..invalid_utf8) }
        ..outside { result = ..error(.reason = ..out_of_bounds) }
    }
}

validate_utf8(.text: StringView) -> (.result: Errable#(UIntNative, (..invalid_utf8))) := {
    offset :: UIntNative = 0
    count :: UIntNative = 0

    while offset < text.length {
        match _utf8_decode(.text = text, .offset = offset).result {
            ..valid payload { offset = offset + payload.decoded.width }
            ..invalid {
                result = ..error(.reason = ..invalid_utf8)
                return
            }
            ..outside { abort }
        }
        count = count + 1
    }

    result = ..ok count
}

utf8_encoded_length(.scalar: UnicodeScalar) -> (.count: UIntNative) := {
    code ::= scalar._value

    if code < 128 {
        count = 1
        return
    }

    if code < 2048 {
        count = 2
        return
    }

    if code < 65536 {
        count = 3
        return
    }

    count = 4
}

-- Validate the entire destination before writing any byte. The scalar's private
-- representation guarantees that arithmetic yields the shortest valid encoding.
utf8_encode(
        .scalar : UnicodeScalar,
        .buffer : ArrayView#(.t: UInt8),
        .offset : UIntNative             = 0
    ) -> (
        .result : Errable#(UIntNative, (..out_of_bounds))
    ) := {
    width ::= utf8_encoded_length(.scalar = scalar).count
    size ::= length(&buffer).count

    if offset > size {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if width > size - offset {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    code ::= scalar._value
    first :: UInt32 = code

    if width == 2 { first = 192 + code / 64 }
    if width == 3 { first = 224 + code / 4096 }
    if width == 4 { first = 240 + code / 262144 }
    pointer ::= unwrap_or_abort(.value = get_rw_ref($&buffer, .index = offset))
    pointer&= unwrap_or_abort(.value = first | convert#(.to: UInt8)(_))
    divisor :: UInt32 = 1

    if width == 3 { divisor = 64 }
    if width == 4 { divisor = 4096 }
    index :: UIntNative = 1

    while index < width {
        pointer ::= unwrap_or_abort(.value = get_rw_ref($&buffer, .index = offset + index))
        pointer&= unwrap_or_abort(.value = [128 + code / divisor % 64] | convert#(.to: UInt8)(_))
        divisor = divisor / 64
        index = index + 1
    }

    result = ..ok width
}

Utf8Decoder: Type = (._text: StringView, ._offset: UIntNative)

implement Init#(
    Utf8Decoder,
    (
        .text : StringView,
    )
) (
        .Result : Type = Utf8Decoder
        .init   = (
                .args : (
                    .text : StringView,
                )
            ) -> (
                .result : Result
            ) {
            text ::= args.text

            result = (._text = text, ._offset = 0)
        }
    )

position(.self: &Utf8Decoder) -> (.count: UIntNative) := { count = self&._offset }

next_codepoint(
        .self : $&Utf8Decoder
    ) -> (
        .result : Errable#(?UnicodeScalar, (..invalid_utf8))
    ) := {
    if self&._offset == self&._text.length {
        result = ..ok ..none
        return
    }

    match _utf8_decode(.text = self&._text, .offset = self&._offset).result {
        ..valid payload {
            self&._offset = self&._offset + payload.decoded.width
            result = ..ok ..some(.value = payload.decoded.scalar)
        }
        ..invalid { result = ..error(.reason = ..invalid_utf8) }
        ..outside { abort }
    }
}

-- Validation borrows bytes rather than freezing or owning them. Callers must
-- keep their contents unchanged while using the validated view and its iterator.
Utf8View: Type = (._text: StringView, ._count: UIntNative)

implement ImplicitlyCopyable#(Utf8View) ()

implement Init#(
    Utf8View,
    (
        .text : StringView,
    )
) (
        .Result : Type = Errable#(Utf8View, (..invalid_utf8))
        .init   = (
                .args : (
                    .text : StringView,
                )
            ) -> (
                .result : Result
            ) {
            text ::= args.text

            count ::= validate_utf8(.text = text)!

            result = ..ok(._text = text, ._count = count)
        }
    )

codepoints(.text: StringView) -> (.result: Errable#(Utf8View, (..invalid_utf8))) := {
    result = Utf8View(.text = text)
}

length(.self: &Utf8View) -> (.count: UIntNative) := { count = self&._count }

utf8_bytes(.self: &Utf8View) -> (.text: StringView) := { text = self&._text }

Utf8Iterator: Type = (._text: StringView, ._offset: UIntNative)

implement Iterable#(Utf8View) (
        .Item         : Type = UnicodeScalar
        .IteratorType : Type = Utf8Iterator

        .to_iterator = (
                .value : &Utf8View
            ) -> (
                .iterator : Utf8Iterator
            ) {
            iterator = (._text = value&._text, ._offset = 0)
        }
    )

implement Iterator#(Utf8Iterator) (
        .Item : Type = UnicodeScalar

        .has_next = (
                .self : &Utf8Iterator
            ) -> (
                .ok : Bool
            ) { ok = self&._offset < self&._text.length }

        .next = (
                .self : $&Utf8Iterator
            ) -> (
                .value : UnicodeScalar
            ) {
            match _utf8_decode(.text = self&._text, .offset = self&._offset).result {
                ..valid payload {
                    value = payload.decoded.scalar
                    self&._offset = self&._offset + payload.decoded.width
                }
                ..invalid { abort }
                ..outside { abort }
            }
        }
    )
