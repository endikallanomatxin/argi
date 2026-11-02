_HttpContentReaderApp := (.failed: Bool, .specific: Bool)

implement Handler#(_HttpContentReaderApp) (
    .Reasons : Type = HttpReasons
    .handle  = (.self: $&_HttpContentReaderApp, .request: $&Request) -> (
        .result : Errable#(Void, Reasons) = ..ok Void()
    ) {
        bytes :: [3]UInt8 = (0, 0, 0)
        match read_exact(.self = request, .buffer = view($&bytes)) {
            ..ok _ { result = respond(.self = request, .body = view(&bytes)) }
            ..error error {
                self&.failed = error.reason == ..stream_read_failed
                match content_failure(.self = request).reason {
                    ..none {}
                    ..some failure { self&.specific = failure.value == ..invalid_chunk }
                }
                result = ..error(.reason = ..invalid_chunk)
            }
        }
    }
)

test http_request_content_block_reader := () -> !() {
    app :: _HttpContentReaderApp = (.failed = false, .specific = false)
    source ::= ByteReader(
        .bytes = string_bytes(
            .text = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\na\0b"
        )
    )
    output :: [256]UInt8 = zeroed#([256]UInt8)()
    writer ::= ByteWriter(.bytes = view($&output))
    serve_stream(.reader = $&source, .writer = $&writer, .handler = $&app)!
    expected: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\na\0b"
    bytes ::= string_bytes(.text = expected)
    testing.expect(position(&writer).count == length(&bytes).count)!
    i :: UIntNative = 0
    while i < length(&bytes).count {
        testing.expect(output[i] == unwrap_or_abort(.value = get(&bytes, .index = i)))!
        i = i + 1
    }
    invalid ::= ByteReader(
        .bytes = string_bytes(
            .text = "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nz\r\n"
        )
    )
    bad_output :: [256]UInt8 = zeroed#([256]UInt8)()
    bad_writer ::= ByteWriter(.bytes = view($&bad_output))
    serve_stream(.reader = $&invalid, .writer = $&bad_writer, .handler = $&app)!
    testing.expect(app.failed and app.specific)!
    prefix ::= string_bytes(.text = "HTTP/1.1 400 Bad Request\r\n")
    testing.expect(position(&bad_writer).count >= length(&prefix).count)!
    i = 0
    while i < length(&prefix).count {
        testing.expect(bad_output[i] == unwrap_or_abort(.value = get(&prefix, .index = i)))!
        i = i + 1
    }
}

_HttpFlushReplyApp := (.calls: UIntNative)

implement Handler#(_HttpFlushReplyApp) (
    .Reasons : Type = HttpReasons
    .handle  = (.self: $&_HttpFlushReplyApp, .request: $&Request) -> (
        .result : Errable#(Void, Reasons) = ..ok Void()
    ) {
        self&.calls = self&.calls + 1
        begin_reply(.self = request, .length = 3)!
        write_reply(.self = request, .body = string_bytes(.text = "abc"))!
        flush_reply(.self = request)!
        finish_reply(.self = request)!
    }
)

test http_request_flush_reply := () -> !() {
    app :: _HttpFlushReplyApp = (.calls = 0)
    source ::= ByteReader(.bytes = string_bytes(.text = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"))
    output :: [128]UInt8 = zeroed#([128]UInt8)()
    writer ::= ByteWriter(.bytes = view($&output))
    serve_stream(.reader = $&source, .writer = $&writer, .handler = $&app)!
    expected ::= string_bytes(
        .text = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\nabc"
    )
    testing.expect(app.calls == 1 and position(&writer).count == length(&expected).count)!
    i :: UIntNative = 0
    while i < length(&expected).count {
        testing.expect(output[i] == unwrap_or_abort(.value = get(&expected, .index = i)))!
        i = i + 1
    }
}
