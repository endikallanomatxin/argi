Reader#(.Stream: Type): Contract = (
    .read_byte : (.self: $&Stream) -> (.result: Errable#(ReadByte, (..stream_read_failed))) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
)

read(
        .self   : $&Reader,
        .buffer : ArrayView#(.t: UInt8),
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    copied :: UIntNative = 0

    while copied < length(&buffer).count {
        match Reader#().read_byte(self)! {
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
