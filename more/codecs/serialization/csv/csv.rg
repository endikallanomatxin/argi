CsvReasons: Type = (..invalid_csv, ..invalid_utf8, ..out_of_memory, ..size_limit_exceeded)

CsvRecord: Type = (.fields: DynamicArray#(.t: String))

implement Deinit#(CsvRecord) (
    .deinit = (.self: $&CsvRecord) -> () {
        while length(&self&.fields).count > 0 {
            discarded ::= ~unwrap_or_abort(.value = pop(.self = $&self&.fields))
        }

        deinit(.self = $&self&.fields)
    }
)

-- Borrowed input must remain unchanged. Records own decoded fields, including
-- embedded line breaks and doubled quotes. Accept CRLF and LF record endings;
-- bare CR is invalid outside quotes. Empty input has no records; a blank line
-- contains one empty field. Encoding and width validation belong to the consumer.
CsvReader: Type = (
    ._text : StringView,
    ._position : UIntNative,
    ._ended : Bool,
    .maximum_field_bytes : UIntNative,
    .maximum_fields      : UIntNative
)

implement Init#(
    CsvReader,
    (
        .text : StringView,
        .maximum_field_bytes : UIntNative  = 1048576,
        .maximum_fields      : UIntNative  = 1024,
    )
) (
    .Result : Type = CsvReader
    .init   = (
        .args : (
            .text : StringView,
            .maximum_field_bytes : UIntNative  = 1048576,
            .maximum_fields      : UIntNative  = 1024,
        )
    ) -> (.result: Result) {
        text ::= args.text
        maximum_field_bytes ::= args.maximum_field_bytes
        maximum_fields ::= args.maximum_fields

        result = (
            ._text = text
            ._position = 0
            ._ended = false
            .maximum_field_bytes = maximum_field_bytes
            .maximum_fields      = maximum_fields
        )
    }
)

-- Errors are terminal, and no partially decoded record escapes.
next#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .self: $&CsvReader, .allocator: $&AllocatorType = reach allocator
) -> (.result: Errable#(?CsvRecord, CsvReasons)) := {
    assume allocator

    if self&._ended or self&._position == byte_length(&self&._text).count {
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
        field ::= DynamicArray#(UInt8)(.capacity = 16)!
        quoted ::= false
        if position < byte_length(&self&._text).count {
            if [
                unwrap_or_abort(.value = bytes_get(.view = &self&._text, .index = position))
                == 34
            ] {
                quoted = true
                position = [position + 1]
            }
        }
        closed ::= false
        while position < byte_length(&self&._text).count {
            byte ::= unwrap_or_abort(
                .value = bytes_get(.view = &self&._text, .index = position)
            )
            if quoted {
                if byte == 34 {
                    position = position + 1
                    if position < byte_length(&self&._text).count {
                        if [
                            unwrap_or_abort(
                                .value = bytes_get(.view = &self&._text, .index = position)
                            )
                            == 34
                        ] {
                            if length(&field).count >= self&.maximum_field_bytes {
                                result = ..error(.reason = ..size_limit_exceeded)
                                return
                            }
                            push(.self = $&field, .value = 34)!
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
            if length(&field).count >= self&.maximum_field_bytes {
                result = ..error(.reason = ..size_limit_exceeded)
                return
            }
            push(.self = $&field, .value = byte)!
            position = position + 1
        }
        if quoted and closed == false {
            result = ..error(.reason = ..invalid_csv)
            return
        }
        text ::= string_from_bytes(.bytes = view(&field))!
        push(.self = $&record.fields, .value = ~text)!
        if position == byte_length(&self&._text).count { break }
        separator ::= unwrap_or_abort(
            .value = bytes_get(.view = &self&._text, .index = position)
        )
        position = position + 1
        if separator == 44 { continue }
        if separator == 10 { break }
        if separator == 13 and position < byte_length(&self&._text).count {
            if [
                unwrap_or_abort(.value = bytes_get(.view = &self&._text, .index = position))
                == 10
            ] {
                position = [position + 1]
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
write_record#(.WriterType: Type: Writer#(WriterType))(
    .writer: $&WriterType, .fields: ArrayView#(.t: StringView)
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()) := {
    index :: UIntNative = 0

    while index < length(&fields).count {
        if index > 0 { Writer#().write_byte(.self = writer, .byte = 44)! }
        text ::= unwrap_or_abort(.value = get(.self = &fields, .index = index))
        Writer#().write_byte(.self = writer, .byte = 34)!
        cursor :: UIntNative = 0
        while cursor < byte_length(&text).count {
            byte ::= unwrap_or_abort(.value = bytes_get(.view = &text, .index = cursor))
            Writer#().write_byte(.self = writer, .byte = byte)!
            if byte == 34 { Writer#().write_byte(.self = writer, .byte = byte)! }
            cursor = cursor + 1
        }
        Writer#().write_byte(.self = writer, .byte = 34)!
        index = index + 1
    }

    write(.self = writer, .value = "\r\n")!
}
