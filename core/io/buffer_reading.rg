BufferReading#(.Stream: Type): Contract = (
    .Result : Type
    .read   : (.self: $&Stream, .buffer: MutableArrayView#(.t: UInt8)) -> (.result: Result)
)

implement#(.Stream: Type: Reader#(Stream)) BufferReading#(Stream) (
    .Result : Type = Errable#(UIntNative, (..stream_read_failed))
    .read   = _reader_read
)

_reader_read#(.Stream: Type: Reader#(Stream))(
    .self: $&Stream, .buffer: MutableArrayView#(.t: UInt8)
) -> (.result: Errable#(UIntNative, (..stream_read_failed))) := {
    copied :: UIntNative = 0

    while copied < length(&buffer).count {
        match Reader#().read_byte(self)! {
            ..end { break }
            ..ok byte {
                target ::= unwrap_or_abort(
                    .value = get_mutable_reference($&buffer, .index = copied)
                )
                target&= byte
                copied = copied + 1
            }
        }
    }

    result = ..ok copied
}
