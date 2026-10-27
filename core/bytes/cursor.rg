-- Cursors borrow initialized storage and advance only after successful access.
ByteReader := (._bytes: ArrayView#(.t: UInt8), ._position: UIntNative)

ByteWriter := (._bytes: MutableArrayView#(.t: UInt8), ._position: UIntNative)

implement Init#(ByteReader, (.bytes: ArrayView#(.t: UInt8))) (
    .Result : Type = ByteReader

    .init = (.args: (.bytes: ArrayView#(.t: UInt8))) -> (.result: Result) {
        bytes ::= args.bytes
        result = (._bytes = bytes, ._position = 0)
    }
)

implement Init#(ByteWriter, (.bytes: MutableArrayView#(.t: UInt8))) (
    .Result : Type = ByteWriter

    .init = (.args: (.bytes: MutableArrayView#(.t: UInt8))) -> (.result: Result) {
        bytes ::= args.bytes
        result = (._bytes = bytes, ._position = 0)
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

read_uint16 := (.self: $&ByteReader, .order: ByteOrder) -> (
    .result : Errable#(UInt16, (..out_of_bounds))
) {
    value_out ::= read_uint16_at(
        .bytes = self&._bytes, .offset = self&._position, .order = order
    )!
    self&._position = self&._position + 2

    result = ..ok value_out
}

read_uint32 := (.self: $&ByteReader, .order: ByteOrder) -> (
    .result : Errable#(UInt32, (..out_of_bounds))
) {
    value_out ::= read_uint32_at(
        .bytes = self&._bytes, .offset = self&._position, .order = order
    )!
    self&._position = self&._position + 4

    result = ..ok value_out
}

read_uint64 := (.self: $&ByteReader, .order: ByteOrder) -> (
    .result : Errable#(UInt64, (..out_of_bounds))
) {
    value_out ::= read_uint64_at(
        .bytes = self&._bytes, .offset = self&._position, .order = order
    )!
    self&._position = self&._position + 8

    result = ..ok value_out
}

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

write_uint16 := (.self: $&ByteWriter, .value: UInt16, .order: ByteOrder) -> (
    .result : Errable#(Void, (..out_of_bounds))
) {
    value_out ::= write_uint16_at(
        .bytes = self&._bytes, .offset = self&._position, .value = value, .order = order
    )!
    self&._position = self&._position + 2

    result = ..ok value_out
}

write_uint32 := (.self: $&ByteWriter, .value: UInt32, .order: ByteOrder) -> (
    .result : Errable#(Void, (..out_of_bounds))
) {
    value_out ::= write_uint32_at(
        .bytes = self&._bytes, .offset = self&._position, .value = value, .order = order
    )!
    self&._position = self&._position + 4

    result = ..ok value_out
}

write_uint64 := (.self: $&ByteWriter, .value: UInt64, .order: ByteOrder) -> (
    .result : Errable#(Void, (..out_of_bounds))
) {
    value_out ::= write_uint64_at(
        .bytes = self&._bytes, .offset = self&._position, .value = value, .order = order
    )!
    self&._position = self&._position + 8

    result = ..ok value_out
}
