Reader: Abstract = (
    read_byte(.self: $&Self) -> (.result: Errable#(ReadByte, (..stream_read_failed)))
)

read(
        .self   : $&Reader,
        .buffer : ArrayView#(.t: UInt8),
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    copied :: UIntNative = 0

    while copied < length(&buffer).count {
        match read_byte(self)! {
            ..end { break }
            ..ok byte {
                target ::= unwrap_or_abort(.value = get_rw_ref($&buffer, .index = copied))
                target&= byte
                copied = copied + 1
            }
        }
    }

    result = ..ok copied
}
