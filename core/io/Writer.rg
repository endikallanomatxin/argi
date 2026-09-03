Writer : Abstract = (
    write_byte(.self: $&Self, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
    flush(.self: $&Self) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
)

write(
    .self: $&Writer,
    .text: &String,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < text&.length {
        wrote ::= write_byte(.self = self, .byte = bytes_get(.string = text, .index = i).byte)
        match wrote {
            ..ok _ {
            }
            ..error & err {
                result = ..error(.reason = err&.reason)
                return
            }
        }
        i = i + 1
    }
    result = ..ok Void()
}

write(
    .self: $&Writer,
    .buffer: ArrayView#(.t: UInt8),
) -> (.result: Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    wrote_count :: UIntNative = 0

    while wrote_count < buffer.length {
        wrote ::= write_byte(.self = self, .byte = buffer[wrote_count])
        match wrote {
            ..ok _ {
                wrote_count = wrote_count + 1
            }
            ..error & err {
                result = ..error(.reason = err&.reason)
                return
            }
        }
    }

    result = ..ok wrote_count
}
