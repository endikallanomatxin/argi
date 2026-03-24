ReadByte : Type = (
    ..ok(.byte: UInt8)
    ..end
)

Reader : Abstract = (
    read_byte(.self: $&Self) -> (.result: ReadByte)
)

Writer : Abstract = (
    write_byte(.self: $&Self, .byte: UInt8) -> ()
    flush(.self: $&Self) -> ()
)

write(
    .self: $&Writer,
    .text: String,
) -> () := {
    i :: UIntNative = 0
    while i < text.length {
        write_byte(.self = self, .byte = bytes_get(.string = &text, .index = i).byte)
        i = i + 1
    }
}
