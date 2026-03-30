..stream_read_failed
..stream_write_failed
..stream_flush_failed
..stream_close_failed

ReadByte : Type = (
    ..ok(.byte: UInt8)
    ..end
)

ReadLine : Type = (
    ..ok(.text: String)
    ..end
)

Reader : Abstract = (
    read_byte(.self: $&Self) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed)))
)

Writer : Abstract = (
    write_byte(.self: $&Self, .byte: UInt8) -> (.result: Errable#(.t: Bool, .reasons: (..stream_write_failed, ..stream_flush_failed)))
    flush(.self: $&Self) -> (.result: Errable#(.t: Bool, .reasons: (..stream_write_failed, ..stream_flush_failed)))
)

write(
    .self: $&Writer,
    .text: String,
) -> (.result: Errable#(.t: Bool, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < text.length {
        wrote ::= write_byte(.self = self, .byte = bytes_get(.string = &text, .index = i).byte)
        if is(.value = wrote, .variant = ..error) {
            result = ..error(.reason = wrote..error.reason)
            return
        }
        i = i + 1
    }
    result = ..ok(.value = true)
}
