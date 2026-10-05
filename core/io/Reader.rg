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
    view :: ArrayView#(.t: UInt8) = buffer

    while copied < length#(.t: UInt8)(&view).count {
        next ::= read_byte(self)
        match next {
            ..ok payload {
                match payload {
                    ..ok byte {
                        ptr ::= trusted_mutable_reference_offset#(.t: UInt8)(
                            .base     = data#(.t: UInt8)(&view).pointer
                            .elements = copied
                        ).reference
                        ptr&= byte
                        copied = copied + 1
                    }
                    ..end {
                        result = ..ok copied
                        return
                    }
                }
            }
            ..error _ {
                result = ..error(.reason = ..stream_read_failed)
                return
            }
        }
    }

    result = ..ok copied
}
