Writer: Abstract = (
    write_byte(.self: $&Self, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    )
    flush(.self: $&Self) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    )
)

write(
        .self : $&Writer,
        .text : StringView,
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    i :: UIntNative = 0

    while i < text.length {
        write_byte(self, .byte = bytes_get(.view = &text, .index = i).byte)!
        i = i + 1
    }

    result = ..ok Void()
}

write(
        .self : $&Writer,
        .text : &String,
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    result = write(self, .text = as_view(text))
}

write(
        .self   : $&Writer,
        .buffer : ArrayView#(.t: UInt8),
    ) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    wrote_count :: UIntNative = 0

    while wrote_count < length(&buffer).count {
        byte ::= unwrap_or_abort(.value = get_ro_ref(&buffer, .index = wrote_count))
        write_byte(self, .byte = byte&)!
        wrote_count = wrote_count + 1
    }

    result = ..ok wrote_count
}
