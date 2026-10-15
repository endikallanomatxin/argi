_reader_block#(.t: Type: Reader#(t))(.self: $&t, .buffer: ArrayView#(.t: UInt8)) -> (
    .result : Errable#(UIntNative, (..stream_read_failed))
) := {
    result = read(self, .buffer = buffer)
}

_writer_block#(.t: Type: Writer#(t))(.self: $&t, .buffer: ArrayViewRO#(.t: UInt8)) -> (
    .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
) := {
    index :: UIntNative = 0

    while index < length(&buffer).count {
        byte ::= unwrap_or_abort(.value = get_ro_ref(&buffer, .index = index))
        Writer#().write_byte(self, .byte = byte&)!
        index = index + 1
    }

    result = ..ok index
}

implement BlockReader#(File) (
    .read_block = (.self: $&File, .buffer: ArrayView#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {
        result = read(self, .buffer = buffer)
    }
)

implement BlockReader#(ProcessStream) (
    .read_block = (.self: $&ProcessStream, .buffer: ArrayView#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {
        result = read(self, .buffer = buffer)
    }
)

implement BlockWriter#(ProcessStream) (
    .write_block = (.self: $&ProcessStream, .buffer: ArrayViewRO#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = _writer_block(self, .buffer = buffer)
    }
)

implement#(.base_type: Type: Reader#(base_type)) BlockReader#(
    BufferedReader#(.base_type: base_type)
) (
    .read_block = (
        .self: $&BufferedReader#(.base_type: base_type), .buffer: ArrayView#(.t: UInt8)
    ) -> (.result: Errable#(UIntNative, (..stream_read_failed))) {
        result = _reader_block(self, .buffer = buffer)
    }
)

implement#(.base_type: Type: Writer#(base_type)) BlockWriter#(
    BufferedWriter#(.base_type: base_type)
) (
    .write_block = (
        .self: $&BufferedWriter#(.base_type: base_type), .buffer: ArrayViewRO#(.t: UInt8)
    ) -> (.result: Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))) {
        result = _writer_block(self, .buffer = buffer)
    }
)
