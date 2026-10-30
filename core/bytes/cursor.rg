-- Cursors borrow initialized storage and advance only after successful access.
ByteReader := (._bytes: ArrayView#(.t: UInt8), ._position: UIntNative)

ByteWriter := (._bytes: MutableArrayView#(.t: UInt8), ._position: UIntNative)

ByteReaderInitArgs: Type = (.bytes: ArrayView#(.t: UInt8))

implement Init#(ByteReader, ByteReaderInitArgs) (
    .Result : Type = ByteReader

    .init = ByteReaderInitArgs -> (.result: Result) {
        _init_bytes ::= bytes
        result = (._bytes = _init_bytes, ._position = 0)
    }
)

ByteWriterInitArgs: Type = (.bytes: MutableArrayView#(.t: UInt8))

implement Init#(ByteWriter, ByteWriterInitArgs) (
    .Result : Type = ByteWriter

    .init = ByteWriterInitArgs -> (.result: Result) {
        _init_bytes ::= bytes
        result = (._bytes = _init_bytes, ._position = 0)
    }
)

_byte_reader_position := (.self: &ByteReader) -> (.count: UIntNative) {
    count = self&._position
}

_byte_writer_position := (.self: &ByteWriter) -> (.count: UIntNative) {
    count = self&._position
}

_byte_reader_remaining := (.self: &ByteReader) -> (.count: UIntNative) {
    count = [length(&self&._bytes).count - self&._position]
}

_byte_writer_remaining := (.self: &ByteWriter) -> (.count: UIntNative) {
    count = [length(&self&._bytes).count - self&._position]
}

_byte_reader_skip := (.self: $&ByteReader, .count: UIntNative) -> (
    .result : Errable#(Void, (..out_of_bounds))
) {

    if count > remaining(self).count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    self&._position = self&._position + count

    result = ..ok Void()
}

_read_uint_cursor := #(.Value: Type: UInt) (.self: $&ByteReader, .order: ByteOrder) -> (
    .result : Errable#(Value, (..out_of_bounds))
) {

    value_out ::= _read_multibyte_uint_at#(.Value: Value)(
        .bytes = self&._bytes, .offset = self&._position, .order = order
    )!
    self&._position = self&._position + size_of(.type = Value)

    result = ..ok value_out
}

read_uint16 := _read_uint_cursor#(.Value: UInt16)
read_uint32 := _read_uint_cursor#(.Value: UInt32)
read_uint64 := _read_uint_cursor#(.Value: UInt64)

_byte_writer_skip := (.self: $&ByteWriter, .count: UIntNative) -> (
    .result : Errable#(Void, (..out_of_bounds))
) {

    if count > remaining(self).count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    self&._position = self&._position + count

    result = ..ok Void()
}

_write_uint_cursor := #(.Value: Type: UInt) (
    .self: $&ByteWriter, .value: Value, .order: ByteOrder
) -> (.result: Errable#(Void, (..out_of_bounds))) {

    value_out ::= _write_multibyte_uint_at#(.Value: Value)(
        .bytes = self&._bytes, .offset = self&._position, .value = value, .order = order
    )!
    self&._position = self&._position + size_of(.type = Value)

    result = ..ok value_out
}

write_uint16 := _write_uint_cursor#(.Value: UInt16)
write_uint32 := _write_uint_cursor#(.Value: UInt32)
write_uint64 := _write_uint_cursor#(.Value: UInt64)
