_HttpOrderSource := (.head: ByteReader, .flushed: &Bool, .delivered: Bool)

implement BlockReader#(_HttpOrderSource) (
    .read_block = (.self: $&_HttpOrderSource, .buffer: MutableArrayView#(UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {
        if length(&buffer).count == 0 {
            result = ..ok 0
            return
        }
        count ::= BlockReader#().read_block(.self = $&self&.head, .buffer = buffer)!
        if count != 0 {
            result = ..ok count
            return
        }
        if self&.delivered {
            result = ..ok 0
            return
        }
        if self&.flushed&== false {
            result = ..error(.reason = ..stream_read_failed)
            return
        }
        target ::= unwrap_or_abort(.value = get_mutable_reference($&buffer, .index = 0))
        target&= 65
        self&.delivered = true
        result = ..ok 1
    }
)

_HttpOrderWriter := (.base: ByteWriter, .flushed: $&Bool)

implement BlockWriter#(_HttpOrderWriter) (
    .write_block = (.self: $&_HttpOrderWriter, .buffer: ArrayView#(UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = BlockWriter#().write_block(.self = $&self&.base, .buffer = buffer)
    }
)

implement Writer#(_HttpOrderWriter) (
    .write_byte = (.self: $&_HttpOrderWriter, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = Writer#().write_byte(.self = $&self&.base, .byte = byte)
    }
    .flush = (.self: $&_HttpOrderWriter) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        self&.flushed&= true
        result = ..ok Void()
    }
)

test http_server_flush_before_body_drain := () -> !() {
    head: StringView = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\n\r\n"
    flushed ::= false
    source :: _HttpOrderSource = (
        .head      = ByteReader(.bytes = string_bytes(.text = head))
        .flushed   = &flushed
        .delivered = false
    )
    output :: [256]UInt8 = zeroed#([256]UInt8)()
    writer :: _HttpOrderWriter = (
        .base    = ByteWriter(.bytes = view($&output))
        .flushed = $&flushed
    )
    app :: _HttpServerTestApp = (.mode = 0, .calls = 0)
    serve_stream(.reader = $&source, .writer = $&writer, .handler = $&app)!
    testing.expect(flushed and source.delivered and app.calls == 1)!
}
