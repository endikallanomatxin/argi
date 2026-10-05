CsvReasons: Type = (..invalid_csv, ..out_of_memory, ..size_limit_exceeded)

CsvRecord: Type = (.fields: DynamicArray#(.t: String))

CsvRecord deinit(.self: $&CsvRecord, .allocator: $&Allocator) -> () := {
    assume allocator

    while length(&self&.fields).count > 0 {
        discarded ::= ~unwrap_or_abort(.value = pop(.self = $&self&.fields))
    }

    deinit(.self = $&self&.fields)
}

-- Borrowed input must remain unchanged. Records own decoded fields, including
-- embedded line breaks and doubled quotes. Accept CRLF and LF record endings;
-- bare CR is invalid outside quotes. Empty input has no records; a blank line
-- contains one empty field. Encoding and width validation belong to the consumer.
CsvReader: Type = (
    ._text               : StringView,
    ._position           : UIntNative,
    ._ended              : Bool,
    .maximum_field_bytes : UIntNative,
    .maximum_fields      : UIntNative
)

CsvReader init(
        .text                : StringView,
        .maximum_field_bytes : UIntNative  = 1048576,
        .maximum_fields      : UIntNative  = 1024
    ) -> (
        .result : CsvReader
    ) := {
    result = (
        ._text               = text
        ._position           = 0
        ._ended              = false
        .maximum_field_bytes = maximum_field_bytes
        .maximum_fields      = maximum_fields
    )
}

-- Errors are terminal, and no partially decoded record escapes.
next(
        .self      : $&CsvReader,
        .allocator : $&Allocator  = reach allocator
    ) -> (
        .result : Errable#(.t: ?CsvRecord, .reasons: CsvReasons)
    ) := {
    assume allocator

    if self&._ended or self&._position == self&._text.length {
        result = ..ok ..none
        return
    }

    self&._ended = true
    fields ::= DynamicArray#(.t: String)(.capacity = 1)!
    record :: CsvRecord = (.fields = ~fields)
    position ::= self&._position

    while true {
        if length(&record.fields).count >= self&.maximum_fields {
            result = ..error(.reason = ..size_limit_exceeded)
            return
        }
        field ::= String(.capacity = 16)!
        quoted ::= false
        if position < self&._text.length {
            if bytes_get(.view = &self&._text, .index = position).byte == 34 {
                quoted = true
                position = [
                    position
                    + 1
                ]
            }
        }
        closed ::= false
        while position < self&._text.length {
            byte ::= bytes_get(.view = &self&._text, .index = position).byte
            if quoted {
                if byte == 34 {
                    position = position + 1
                    if position < self&._text.length {
                        if bytes_get(.view = &self&._text, .index = position).byte == 34 {
                            if field.length >= self&.maximum_field_bytes {
                                result = ..error(.reason = ..size_limit_exceeded)
                                return
                            }
                            push_byte(.self = $&field, .byte = 34)!
                            position = position + 1
                            continue
                        }
                    }
                    closed = true
                    break
                }
            } else {
                if byte == 44 or byte == 10 or byte == 13 { break }
                if byte == 34 {
                    result = ..error(.reason = ..invalid_csv)
                    return
                }
            }
            if field.length >= self&.maximum_field_bytes {
                result = ..error(.reason = ..size_limit_exceeded)
                return
            }
            push_byte(.self = $&field, .byte = byte)!
            position = position + 1
        }
        if quoted and closed == false {
            result = ..error(.reason = ..invalid_csv)
            return
        }
        push(.self = $&record.fields, .value = ~field)!
        if position == self&._text.length { break }
        separator ::= bytes_get(.view = &self&._text, .index = position).byte
        position = position + 1
        if separator == 44 { continue }
        if separator == 10 { break }
        if separator == 13 and position < self&._text.length {
            if bytes_get(.view = &self&._text, .index = position).byte == 10 {
                position = [
                    position
                    + 1
                ]
                break
            }
        }
        result = ..error(.reason = ..invalid_csv)
        return
    }

    self&._position = position
    self&._ended = false

    result = ..ok ..some(.value = ~record)
}

-- Quote every field for unambiguous output. Writes may make partial progress.
write_record(
        .writer : $&Writer,
        .fields : ArrayViewRO#(.t: StringView)
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) := {
    index :: UIntNative = 0

    while index < length(&fields).count {
        if index > 0 { write_byte(.self = writer, .byte = 44)! }
        text ::= unwrap_or_abort(.value = get(.self = &fields, .index = index))
        write_byte(.self = writer, .byte = 34)!
        cursor :: UIntNative = 0
        while cursor < text.length {
            byte ::= bytes_get(.view = &text, .index = cursor).byte
            write_byte(.self = writer, .byte = byte)!
            if byte == 34 { write_byte(.self = writer, .byte = byte)! }
            cursor = cursor + 1
        }
        write_byte(.self = writer, .byte = 34)!
        index = index + 1
    }

    write(.self = writer, .text = "\r\n")!
}
