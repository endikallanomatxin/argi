-- Memory cursors implement the stream protocols without acquiring capabilities
-- or storage. They retain the same backing-view lifetime as binary operations.
ByteReader implements Reader
ByteReader implements BlockReader
ByteWriter implements Writer
ByteWriter implements BlockWriter

read_byte(
        .self : $&ByteReader
    ) -> (
        .result : Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) := {
    if remaining(.self = self).count == 0 {
        result = ..ok ..end
        return
    }
    byte ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._bytes, .index = self&._position))
    self&._position = self&._position + 1
    result = ..ok ..ok byte&
}

write_byte(
        .self : $&ByteWriter,
        .byte : UInt8
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) := {
    if remaining(.self = self).count == 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    target ::= unwrap_or_abort(
        .value = get_rw_ref(.self = $&self&._bytes, .index = self&._position)
    )
    target&= byte
    self&._position = self&._position + 1
}

flush(
        .self : $&ByteWriter
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) := {}

read_block(
        .self   : $&ByteReader,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := {
    count ::= remaining(.self = self).count
    size ::= length(.self = &buffer).count
    if size < count { count = size }
    index :: UIntNative = 0
    while index < count {
        source ::= unwrap_or_abort(
            .value = get_ro_ref(
                .self  = &self&._bytes
                .index = [
                    self&._position
                    + index
                ]
            )
        )
        target ::= unwrap_or_abort(.value = get_rw_ref(.self = $&buffer, .index = index))
        target&= source&
        index = index + 1
    }
    self&._position = self&._position + count
    result = ..ok count
}

write_block(
        .self   : $&ByteWriter,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    count ::= remaining(.self = self).count
    size ::= length(.self = &buffer).count
    if size < count { count = size }
    if count == 0 and size != 0 {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    index :: UIntNative = 0
    while index < count {
        source ::= unwrap_or_abort(.value = get_ro_ref(.self = &buffer, .index = index))
        target ::= unwrap_or_abort(
            .value = get_rw_ref(
                .self  = $&self&._bytes
                .index = [
                    self&._position
                    + index
                ]
            )
        )
        target&= source&
        index = index + 1
    }
    self&._position = self&._position + count
    result = ..ok count
}
