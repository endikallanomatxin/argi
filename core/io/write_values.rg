implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, StringView) (
        .Result      : Type = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
        .write_value = (
                .self  : $&Stream,
                .value : StringView
            ) -> (
                .result : Result
            ) {
            i :: UIntNative = 0
            while i < value.length {
                Writer#().write_byte(self, .byte = bytes_get(.view = &value, .index = i).byte)!
                i = i + 1
            }
            result = ..ok Void()
        }
    )

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, &String) (
        .Result      : Type = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
        .write_value = (
                .self  : $&Stream,
                .value : &String
            ) -> (
                .result : Result
            ) {
            result = write(.self = self, .value = as_view(value))
        }
    )

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, ArrayView#(.t: UInt8)) (
        .Result      : Type = Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
        .write_value = (
                .self  : $&Stream,
                .value : ArrayView#(.t: UInt8)
            ) -> (
                .result : Result
            ) {
            wrote_count :: UIntNative = 0
            while wrote_count < length(&value).count {
                byte ::= unwrap_or_abort(.value = get_ro_ref(&value, .index = wrote_count))
                Writer#().write_byte(self, .byte = byte&)!
                wrote_count = wrote_count + 1
            }
            result = ..ok wrote_count
        }
    )
