-- Cursors borrow initialized storage and advance only after successful access.
ByteReader: Type = (._bytes: ArrayViewRO#(.t: UInt8), ._position: UIntNative)

ByteWriter: Type = (._bytes: ArrayView#(.t: UInt8), ._position: UIntNative)

ByteReader init(.bytes: ArrayViewRO#(.t: UInt8)) -> (.result: ByteReader) := {
    result = (._bytes = bytes, ._position = 0)
}

ByteWriter init(.bytes: ArrayView#(.t: UInt8)) -> (.result: ByteWriter) := {
    result = (._bytes = bytes, ._position = 0)
}

position(.self: &ByteReader) -> (.count: UIntNative) := { count = self&._position }

position(.self: &ByteWriter) -> (.count: UIntNative) := { count = self&._position }

remaining(.self: &ByteReader) -> (.count: UIntNative) := {
    count = [
        length(.self = &self&._bytes).count
        - self&._position
    ]
}

remaining(.self: &ByteWriter) -> (.count: UIntNative) := {
    count = [
        length(.self = &self&._bytes).count
        - self&._position
    ]
}

skip(
        .self  : $&ByteReader,
        .count : UIntNative
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    if count > remaining(.self = self).count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    self&._position = self&._position + count
    result = ..ok Void()
}

read_uint16(
        .self  : $&ByteReader,
        .order : ByteOrder
    ) -> (
        .result : Errable#(.t: UInt16, .reasons: (..out_of_bounds))
    ) := {
    value_out ::= read_uint16(.bytes = self&._bytes, .offset = self&._position, .order = order)!
    self&._position = self&._position + 2
    result = ..ok value_out
}

read_uint32(
        .self  : $&ByteReader,
        .order : ByteOrder
    ) -> (
        .result : Errable#(.t: UInt32, .reasons: (..out_of_bounds))
    ) := {
    value_out ::= read_uint32(.bytes = self&._bytes, .offset = self&._position, .order = order)!
    self&._position = self&._position + 4
    result = ..ok value_out
}

read_uint64(
        .self  : $&ByteReader,
        .order : ByteOrder
    ) -> (
        .result : Errable#(.t: UInt64, .reasons: (..out_of_bounds))
    ) := {
    value_out ::= read_uint64(.bytes = self&._bytes, .offset = self&._position, .order = order)!
    self&._position = self&._position + 8
    result = ..ok value_out
}

skip(
        .self  : $&ByteWriter,
        .count : UIntNative
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    if count > remaining(.self = self).count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    self&._position = self&._position + count
    result = ..ok Void()
}

write_uint16(
        .self  : $&ByteWriter,
        .value : UInt16,
        .order : ByteOrder
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    value_out ::= write_uint16(
        .bytes  = self&._bytes
        .offset = self&._position
        .value  = value
        .order  = order
    )!
    self&._position = self&._position + 2
    result = ..ok value_out
}

write_uint32(
        .self  : $&ByteWriter,
        .value : UInt32,
        .order : ByteOrder
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    value_out ::= write_uint32(
        .bytes  = self&._bytes
        .offset = self&._position
        .value  = value
        .order  = order
    )!
    self&._position = self&._position + 4
    result = ..ok value_out
}

write_uint64(
        .self  : $&ByteWriter,
        .value : UInt64,
        .order : ByteOrder
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_bounds))
    ) := {
    value_out ::= write_uint64(
        .bytes  = self&._bytes
        .offset = self&._position
        .value  = value
        .order  = order
    )!
    self&._position = self&._position + 8
    result = ..ok value_out
}
