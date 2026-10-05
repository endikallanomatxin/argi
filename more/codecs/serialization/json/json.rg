JsonReasons: Type = (..invalid_json, ..json_depth_exceeded, ..invalid_utf8)

_byte(.text: StringView, .position: UIntNative) -> (.value: UInt8) := {
    value = bytes_get(.view = &text, .index = position).byte
}

_space(.text: StringView, .position: UIntNative) -> (.next: UIntNative) := {
    next = position

    while next < text.length {
        byte ::= _byte(.text = text, .position = next).value
        if byte != 32 and byte != 9 and byte != 10 and byte != 13 { return }
        next = next + 1
    }
}

_hex(.byte: UInt8) -> (.value: UInt32 = 16) := {
    if byte >= 48 and byte <= 57 {
        value = UInt32(.value = byte - 48)
        return
    }

    if byte >= 65 and byte <= 70 {
        value = UInt32(.value = byte - 55)
        return
    }

    if byte >= 97 and byte <= 102 { value = UInt32(.value = byte - 87) }
}

_quad(
        .text     : StringView,
        .position : UIntNative
    ) -> (
        .result : Errable#(.t: UInt32, .reasons: JsonReasons)
    ) := {
    if position > text.length or text.length - position < 4 {
        result = ..error(.reason = ..invalid_json)
        return
    }

    value :: UInt32 = 0
    offset :: UIntNative = 0

    while offset < 4 {
        digit ::= _hex(.byte = _byte(.text = text, .position = position + offset).value).value
        if digit == 16 {
            result = ..error(.reason = ..invalid_json)
            return
        }
        value = value * 16 + digit
        offset = offset + 1
    }

    result = ..ok value
}

-- Return the byte after a closing quote. Reject isolated UTF-16 surrogates:
-- the accepted profile always denotes Unicode scalar values.
_string_end(
        .text     : StringView,
        .position : UIntNative
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: JsonReasons)
    ) := {
    cursor ::= position + 1

    while cursor < text.length {
        byte ::= _byte(.text = text, .position = cursor).value
        cursor = cursor + 1
        if byte == 34 {
            result = ..ok cursor
            return
        }
        if byte < 32 {
            result = ..error(.reason = ..invalid_json)
            return
        }
        if byte == 92 {
            if cursor == text.length {
                result = ..error(.reason = ..invalid_json)
                return
            }
            escape ::= _byte(.text = text, .position = cursor).value
            cursor = cursor + 1
            if escape == 117 {
                unit ::= _quad(.text = text, .position = cursor)!
                cursor = cursor + 4
                if unit >= 56320 and unit <= 57343 {
                    result = ..error(.reason = ..invalid_json)
                    return
                }
                if unit >= 55296 and unit <= 56319 {
                    if text.length - cursor < 6 {
                        result = ..error(.reason = ..invalid_json)
                        return
                    }
                    if [
                        _byte(.text = text, .position = cursor).value != 92
                        or _byte(
                            .text     = text
                            .position = cursor + 1
                        ).value != 117
                    ] {
                        result = ..error(.reason = ..invalid_json)
                        return
                    }
                    low ::= _quad(.text = text, .position = cursor + 2)!
                    if low < 56320 or low > 57343 {
                        result = ..error(.reason = ..invalid_json)
                        return
                    }
                    cursor = cursor + 6
                }
            } else {
                if [
                    escape != 34
                    and escape != 92
                    and escape != 47
                    and escape != 98
                    and escape != 102
                    and escape != 110
                    and escape != 114
                    and escape != 116
                ] {
                    result = ..error(.reason = ..invalid_json)
                    return
                }
            }
        }
    }

    result = ..error(.reason = ..invalid_json)
}

_digit(.byte: UInt8) -> (.value: Bool) := { value = byte >= 48 and byte <= 57 }

_number_end(
        .text     : StringView,
        .position : UIntNative
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: JsonReasons)
    ) := {
    cursor ::= position

    if _byte(.text = text, .position = cursor).value == 45 { cursor = cursor + 1 }
    if cursor == text.length {
        result = ..error(.reason = ..invalid_json)
        return
    }

    byte ::= _byte(.text = text, .position = cursor).value

    if byte == 48 { cursor = cursor + 1 } else {
        if byte < 49 or byte > 57 {
            result = ..error(.reason = ..invalid_json)
            return
        }
        while cursor < text.length {
            if _digit(.byte = _byte(.text = text, .position = cursor).value).value == false {
                break
            }
            cursor = cursor + 1
        }
    }

    if cursor < text.length {
        if _byte(.text = text, .position = cursor).value == 46 {
            cursor = cursor + 1
            start ::= cursor
            while cursor < text.length {
                if _digit(.byte = _byte(.text = text, .position = cursor).value).value == false {
                    break
                }
                cursor = cursor + 1
            }
            if start == cursor {
                result = ..error(.reason = ..invalid_json)
                return
            }
        }
    }

    if cursor < text.length {
        exponent ::= _byte(.text = text, .position = cursor).value
        if exponent == 101 or exponent == 69 {
            cursor = cursor + 1
            if cursor < text.length {
                sign ::= _byte(.text = text, .position = cursor).value
                if sign == 43 or sign == 45 { cursor = cursor + 1 }
            }
            start ::= cursor
            while cursor < text.length {
                if _digit(.byte = _byte(.text = text, .position = cursor).value).value == false {
                    break
                }
                cursor = cursor + 1
            }
            if start == cursor {
                result = ..error(.reason = ..invalid_json)
                return
            }
        }
    }

    result = ..ok cursor
}

_literal(
        .text     : StringView,
        .position : UIntNative,
        .expected : StringView
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: JsonReasons)
    ) := {
    if text.length - position < expected.length {
        result = ..error(.reason = ..invalid_json)
        return
    }

    offset :: UIntNative = 0

    while offset < expected.length {
        if [
            _byte(.text = text, .position = position + offset).value
            != _byte(
                .text     = expected
                .position = offset
            ).value
        ] {
            result = ..error(.reason = ..invalid_json)
            return
        }
        offset = offset + 1
    }

    end ::= position + expected.length

    result = ..ok end
}

_value_end(
        .text     : StringView,
        .position : UIntNative,
        .depth    : UIntNative,
        .maximum  : UIntNative
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: JsonReasons)
    ) := {
    cursor ::= _space(.text = text, .position = position).next

    if cursor == text.length {
        result = ..error(.reason = ..invalid_json)
        return
    }

    byte ::= _byte(.text = text, .position = cursor).value

    if byte == 34 {
        result = _string_end(.text = text, .position = cursor)
        return
    }

    if byte == 116 {
        result = _literal(.text = text, .position = cursor, .expected = "true")
        return
    }

    if byte == 102 {
        result = _literal(.text = text, .position = cursor, .expected = "false")
        return
    }

    if byte == 110 {
        result = _literal(.text = text, .position = cursor, .expected = "null")
        return
    }

    if byte != 91 and byte != 123 {
        result = _number_end(.text = text, .position = cursor)
        return
    }

    if depth == maximum {
        result = ..error(.reason = ..json_depth_exceeded)
        return
    }

    object ::= byte == 123
    closing :: UInt8 = 93

    if object { closing = 125 }
    cursor = _space(.text = text, .position = cursor + 1).next

    if cursor < text.length {
        if _byte(.text = text, .position = cursor).value == closing {
            end ::= cursor + 1
            result = ..ok end
            return
        }
    }

    while true {
        if object {
            if cursor == text.length {
                result = ..error(.reason = ..invalid_json)
                return
            }
            if _byte(.text = text, .position = cursor).value != 34 {
                result = ..error(.reason = ..invalid_json)
                return
            }
            cursor = _string_end(.text = text, .position = cursor)!
            cursor = _space(.text = text, .position = cursor).next
            if cursor == text.length {
                result = ..error(.reason = ..invalid_json)
                return
            }
            if _byte(.text = text, .position = cursor).value != 58 {
                result = ..error(.reason = ..invalid_json)
                return
            }
            cursor = cursor + 1
        }
        cursor = _value_end(
            .text     = text
            .position = cursor
            .depth    = depth + 1
            .maximum  = maximum
        )!
        cursor = _space(.text = text, .position = cursor).next
        if cursor == text.length {
            result = ..error(.reason = ..invalid_json)
            return
        }
        separator ::= _byte(.text = text, .position = cursor).value
        cursor = cursor + 1
        if separator == closing {
            result = ..ok cursor
            return
        }
        if separator != 44 {
            result = ..error(.reason = ..invalid_json)
            return
        }
        cursor = _space(.text = text, .position = cursor).next
    }
}

-- Validate exactly one complete UTF-8 JSON value without allocating. Preserve
-- number lexemes rather than converting to a fixed-width representation.
-- Duplicate object keys are accepted. Recursion is bounded to at most 256
-- containers, independently of the caller's requested limit.
validate(
        .text          : StringView,
        .maximum_depth : UIntNative  = 64
    ) -> (
        .result : Errable#(.t: Void, .reasons: JsonReasons) = ..ok Void()
    ) := {
    validate_utf8(.text = text)!

    if maximum_depth > 256 {
        result = ..error(.reason = ..json_depth_exceeded)
        return
    }

    end ::= _value_end(.text = text, .position = 0, .depth = 0, .maximum = maximum_depth)!

    if _space(.text = text, .position = end).next != text.length {
        result = ..error(.reason = ..invalid_json)
    }
}

JsonToken: Type = (.kind: UInt8, .lexeme: StringView)

JsonToken implements ImplicitlyCopyable

-- Kind is the first byte: punctuation, quote, literal initial, or number
-- initial. Lexemes borrow the complete validated input, including quotes.
-- Callers must preserve those bytes for the cursor's entire lifetime.
JsonCursor: Type = (._text: StringView, ._position: UIntNative)

JsonCursor init(
        .text          : StringView,
        .maximum_depth : UIntNative  = 64
    ) -> (
        .result : Errable#(.t: JsonCursor, .reasons: JsonReasons)
    ) := {
    validate(.text = text, .maximum_depth = maximum_depth)!

    result = ..ok(._text = text, ._position = 0)
}

next(.self: $&JsonCursor) -> (.result: Errable#(.t: ?JsonToken, .reasons: JsonReasons)) := {
    start ::= _space(.text = self&._text, .position = self&._position).next

    if start == self&._text.length {
        result = ..ok ..none
        return
    }

    byte ::= _byte(.text = self&._text, .position = start).value
    end ::= start + 1

    if byte == 34 { end = _string_end(.text = self&._text, .position = start)! } else {
        if byte == 116 { end = start + 4 } else {
            if byte == 102 { end = start + 5 } else {
                if byte == 110 { end = start + 4 } else {
                    if byte == 45 or _digit(.byte = byte).value {
                        end = _number_end(.text = self&._text, .position = start)!
                    }
                }
            }
        }
    }

    lexeme :: StringView = (
        .data   = string_view_byte_address(.self = &self&._text, .index = start).reference
        .length = end - start
    )
    self&._position = end

    result = ..ok ..some(.value = (.kind = byte, .lexeme = lexeme))
}

-- Decode exactly one JSON string into independent UTF-8 storage.
decode_string(
        .text      : StringView,
        .allocator : $&Allocator = reach allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..invalid_json, ..json_depth_exceeded, ..invalid_utf8, ..out_of_memory)
        )
    ) := {
    assume allocator
    validate(.text = text, .maximum_depth = 0)!
    start ::= _space(.text = text, .position = 0).next

    if _byte(.text = text, .position = start).value != 34 {
        result = ..error(.reason = ..invalid_json)
        return
    }

    end ::= _string_end(.text = text, .position = start)!
    decoded ::= String(.capacity = end - start)!
    cursor ::= start + 1

    while cursor < end - 1 {
        byte ::= _byte(.text = text, .position = cursor).value
        cursor = cursor + 1
        if byte != 92 {
            push_byte(.self = $&decoded, .byte = byte)!
            continue
        }
        escape ::= _byte(.text = text, .position = cursor).value
        cursor = cursor + 1
        if escape == 117 {
            code ::= _quad(.text = text, .position = cursor)!
            cursor = cursor + 4
            if code >= 55296 and code <= 56319 {
                low ::= _quad(.text = text, .position = cursor + 2)!
                code = 65536 + [code - 55296] * 1024 + [low - 56320]
                cursor = cursor + 6
            }
            if code < 128 {
                push_byte(
                    .self = $&decoded
                    .byte = unwrap_or_abort(.value = UInt8(.value = code))
                )!
            } else {
                width :: UIntNative = 2
                divisor :: UInt32 = 64
                prefix :: UInt32 = 192
                if code >= 2048 {
                    width = 3
                    divisor = 4096
                    prefix = 224
                }
                if code >= 65536 {
                    width = 4
                    divisor = 262144
                    prefix = 240
                }
                first ::= unwrap_or_abort(.value = UInt8(.value = prefix + code / divisor))
                push_byte(.self = $&decoded, .byte = first)!
                continuation :: UInt32 = 128
                offset :: UIntNative = 1
                while offset < width {
                    divisor = divisor / 64
                    next_byte ::= unwrap_or_abort(
                        .value = UInt8(.value = continuation + code / divisor % 64)
                    )
                    push_byte(.self = $&decoded, .byte = next_byte)!
                    offset = offset + 1
                }
            }
        } else {
            if escape == 98 { escape = 8 }
            if escape == 102 { escape = 12 }
            if escape == 110 { escape = 10 }
            if escape == 114 { escape = 13 }
            if escape == 116 { escape = 9 }
            push_byte(.self = $&decoded, .byte = escape)!
        }
    }

    result = ..ok ~decoded
}

_hex_ascii(.value: UInt8) -> (.byte: UInt8) := {
    byte = value + 48

    if value >= 10 { byte = value + 87 }
}

-- Validate input before writing; native writer failures can leave a prefix.
write_string(
        .writer : $&Writer,
        .text   : StringView
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (..invalid_utf8, ..stream_write_failed, ..stream_flush_failed)
        ) = ..ok Void()
    ) := {
    validate_utf8(.text = text)!
    write_byte(.self = writer, .byte = 34)!
    cursor :: UIntNative = 0

    while cursor < text.length {
        byte ::= _byte(.text = text, .position = cursor).value
        if byte < 32 {
            write(.self = writer, .text = "\\u00")!
            write_byte(.self = writer, .byte = _hex_ascii(.value = byte / 16).byte)!
            write_byte(.self = writer, .byte = _hex_ascii(.value = byte % 16).byte)!
        } else {
            if byte == 34 or byte == 92 { write_byte(.self = writer, .byte = 92)! }
            write_byte(.self = writer, .byte = byte)!
        }
        cursor = cursor + 1
    }

    write_byte(.self = writer, .byte = 34)!
}
