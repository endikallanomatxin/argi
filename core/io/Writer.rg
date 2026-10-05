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
        wrote ::= write_byte(.self = self, .byte = bytes_get(.view = &text, .index = i).byte)
        match wrote {
            ..ok _ {
            }
            ..error&err {
                result = ..error(.reason = err&.reason)
                return
            }
        }
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
    result = write(.self = self, .text = as_view(text))
}

write(
        .self   : $&Writer,
        .buffer : ArrayView#(.t: UInt8),
    ) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    wrote_count :: UIntNative = 0

    while wrote_count < length#(.t: UInt8)(.self = &buffer).count {
        ptr ::= trusted_reference_offset#(.t: UInt8)(
            .base     = read_reference#(.t: UInt8)(.base = data#(.t: UInt8)(.self = &buffer).pointer).reference
            .elements = wrote_count
        ).reference
        wrote ::= write_byte(.self = self, .byte = ptr&)
        match wrote {
            ..ok _ {
                wrote_count = wrote_count + 1
            }
            ..error&err {
                result = ..error(.reason = err&.reason)
                return
            }
        }
    }

    result = ..ok wrote_count
}
