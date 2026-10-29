_reader_block := #(.t: Type: Reader#(t)) (
    .self         : $&t,
    .buffer       : MutableArrayView#(.t: UInt8),
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(UIntNative, (..stream_read_failed))) {
    assume error_tracer

    result = read(self, .buffer = buffer)
}

_writer_block := #(.t: Type: Writer#(t)) (
    .self         : $&t,
    .buffer       : ArrayView#(.t: UInt8),
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))) {
    assume error_tracer

    index :: UIntNative = 0

    while index < length(&buffer).count {
        byte ::= unwrap_or_abort(.value = get_reference(&buffer, .index = index))
        Writer#().write_byte(self, .byte = byte&)!
        index = index + 1
    }

    result = ..ok index
}

implement BlockReader#(File) (
    .read_block = _read_file
)

implement BlockReader#(ProcessStream) (
    .read_block = _reader_block
)

implement BlockWriter#(ProcessStream) (
    .write_block = _writer_block
)

implement#(.base_type: Type: Reader#(base_type)) BlockReader#(
    BufferedReader#(.base_type: base_type)
) (
    .read_block = _reader_block
)

implement#(.base_type: Type: Writer#(base_type)) BlockWriter#(
    BufferedWriter#(.base_type: base_type)
) (
    .write_block = _writer_block
)
