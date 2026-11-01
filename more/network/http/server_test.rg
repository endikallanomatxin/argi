_HttpServerTestApp := (.mode: UInt8, .calls: UIntNative)

implement Handler#(_HttpServerTestApp) (
    .Reasons : Type = (..application_failure)
    .handle  = (.self: $&_HttpServerTestApp, .request: $&Request) -> (
        .result : Errable#(Void, Reasons) = ..ok Void()
    ) {
        self&.calls = self&.calls + 1
        if self&.mode == 1 { return }
        if self&.mode == 2 {
            result = ..error(.reason = ..application_failure)
            return
        }
        if self&.mode == 8 {
            match respond(
                .self = request, .status = 204, .body = string_bytes(.text = "invalid")
            ) {
                ..ok _ { abort }
                ..error _ { result = ..error(.reason = ..application_failure) }
            }
            return
        }
        if self&.mode == 3 {
            bytes :: [3]UInt8 = (0, 0, 0)
            match read_content(.self = request, .buffer = view($&bytes)) {
                ..error _ {
                    result = ..error(.reason = ..application_failure)
                    return
                }
                ..ok count {
                    if count != 3 {
                        result = ..error(.reason = ..application_failure)
                        return
                    }
                }
            }
            match respond(.self = request, .body = view(&bytes)) {
                ..ok _ {} ..error _ { result = ..error(.reason = ..application_failure) }
            }
            return
        }
        if self&.mode >= 4 and self&.mode <= 6 {
            match begin_reply(.self = request, .length = 3) {
                ..ok _ {} ..error _ {
                    result = ..error(.reason = ..application_failure)
                    return
                }
            }
            if self&.mode == 6 { return }
            text :: StringView = "abc"
            if self&.mode == 5 { text = "abcd" }
            match write_reply(.self = request, .body = string_bytes(.text = text)) {
                ..ok _ {} ..error _ {
                    result = ..error(.reason = ..application_failure)
                    return
                }
            }
            match finish_reply(.self = request) {
                ..ok _ {} ..error _ { result = ..error(.reason = ..application_failure) }
            }
            return
        }
        match respond_text(.self = request, .text = "Hello") {
            ..ok _ {} ..error _ {
                result = ..error(.reason = ..application_failure)
                return
            }
        }
        if self&.mode == 9 {
            result = ..error(.reason = ..application_failure)
            return
        }
        if self&.mode == 7 {
            match respond_text(.self = request, .text = "second") {
                ..ok _ { result = ..error(.reason = ..application_failure) }
                ..error _ {}
            }
        }
    }
)

_http_test_server_case := (
    .wire: StringView, .mode: UInt8, .expected: StringView, .expected_calls: UIntNative
) -> !() {
    source ::= ByteReader(.bytes = string_bytes(.text = wire))
    output :: [1024]UInt8 = zeroed#([1024]UInt8)()
    writer ::= ByteWriter(.bytes = view($&output))
    app :: _HttpServerTestApp = (.mode = mode, .calls = 0)
    serve_stream(.reader = $&source, .writer = $&writer, .handler = $&app)!
    testing.expect(app.calls == expected_calls)!
    expected_bytes ::= string_bytes(.text = expected)
    testing.expect(position(&writer).count == length(&expected_bytes).count)!
    i :: UIntNative = 0
    while i < length(&expected_bytes).count {
        testing.expect(output[i] == unwrap_or_abort(.value = get(&expected_bytes, .index = i)))!
        i = i + 1
    }
}

test http_server_stream := () -> !() {
    request_text: StringView = "GET / HTTP/1.1\r\nHost: example\r\n\r\n"
    ok: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello"
    _http_test_server_case(.wire = request_text, .mode = 0, .expected = ok, .expected_calls = 1)!
    _http_test_server_case(.wire = request_text, .mode = 7, .expected = ok, .expected_calls = 1)!
    _http_test_server_case(
        .wire           = "HEAD / HTTP/1.1\r\nHost: example\r\n\r\n"
        .mode           = 0
        .expected       = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
        .expected_calls = 1
    )!
    _http_test_server_case(
        .wire           = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\na\0b"
        .mode           = 3
        .expected       = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\na\0b"
        .expected_calls = 1
    )!
    _http_test_server_case(
        .wire           = request_text
        .mode           = 4
        .expected       = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\nabc"
        .expected_calls = 1
    )!
}

_http_test_server_status := (
    .wire: StringView, .mode: UInt8, .prefix: StringView, .expected_calls: UIntNative
) -> !() {
    source ::= ByteReader(.bytes = string_bytes(.text = wire))
    output :: [1024]UInt8 = zeroed#([1024]UInt8)()
    writer ::= ByteWriter(.bytes = view($&output))
    app :: _HttpServerTestApp = (.mode = mode, .calls = 0)
    serve_stream(.reader = $&source, .writer = $&writer, .handler = $&app)!
    testing.expect(app.calls == expected_calls)!
    expected ::= string_bytes(.text = prefix)
    testing.expect(position(&writer).count >= length(&expected).count)!
    i :: UIntNative = 0
    while i < length(&expected).count {
        testing.expect(output[i] == unwrap_or_abort(.value = get(&expected, .index = i)))!
        i = i + 1
    }
}

test http_server_errors := () -> !() {
    request_text: StringView = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
    _http_test_server_status(
        .wire           = "GET / HTTP/1.1\r\n\r\n"
        .mode           = 0
        .prefix         = "HTTP/1.1 400 "
        .expected_calls = 0
    )!
    _http_test_server_status(
        .wire           = "POST / HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\n\r\n"
        .mode           = 0
        .prefix         = "HTTP/1.1 417 "
        .expected_calls = 0
    )!
    _http_test_server_status(
        .wire = request_text, .mode = 1, .prefix = "HTTP/1.1 500 ", .expected_calls = 1
    )!
    _http_test_server_status(
        .wire = request_text, .mode = 2, .prefix = "HTTP/1.1 500 ", .expected_calls = 1
    )!
    _http_test_server_status(
        .wire           = "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nz\r\n"
        .mode           = 3
        .prefix         = "HTTP/1.1 400 "
        .expected_calls = 1
    )!
    _http_test_server_status(
        .wire           = "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n100001\r\n"
        .mode           = 3
        .prefix         = "HTTP/1.1 413 "
        .expected_calls = 1
    )!
    _http_test_server_status(
        .wire = request_text, .mode = 8, .prefix = "HTTP/1.1 500 ", .expected_calls = 1
    )!
    _http_test_server_case(
        .wire           = "HEAD / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nz\r\n"
        .mode           = 3
        .expected       = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 15\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
        .expected_calls = 1
    )!

}

test http_server_partial_response := () -> !() {
    request_text: StringView = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
    expected: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\n"
    expected_bytes ::= string_bytes(.text = expected)
    mode :: UInt8 = 5
    while mode <= 6 {
        source ::= ByteReader(.bytes = string_bytes(.text = request_text))
        output :: [1024]UInt8 = zeroed#([1024]UInt8)()
        writer ::= ByteWriter(.bytes = view($&output))
        app :: _HttpServerTestApp = (.mode = mode, .calls = 0)
        match serve_stream(.reader = $&source, .writer = $&writer, .handler = $&app) {
            ..ok _ { abort } ..error error { testing.expect(error.reason == ..invalid_state)! }
        }
        testing.expect(app.calls == 1)!
        testing.expect(position(&writer).count == length(&expected_bytes).count)!
        i :: UIntNative = 0
        while i < length(&expected_bytes).count {
            testing.expect(
                [output[i] == unwrap_or_abort(.value = get(&expected_bytes, .index = i))]
            )!
            i = i + 1
        }
        mode = mode + 1
    }
}

test http_server_handler_state := () -> !() {
    request_text: StringView = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
    app :: _HttpServerTestApp = (.mode = 0, .calls = 0)
    first_source ::= ByteReader(.bytes = string_bytes(.text = request_text))
    first_bytes :: [256]UInt8 = zeroed#([256]UInt8)()
    first_writer ::= ByteWriter(.bytes = view($&first_bytes))
    serve_stream(.reader = $&first_source, .writer = $&first_writer, .handler = $&app)!
    testing.expect(app.calls == 1)!
    second_source ::= ByteReader(.bytes = string_bytes(.text = request_text))
    second_bytes :: [256]UInt8 = zeroed#([256]UInt8)()
    second_writer ::= ByteWriter(.bytes = view($&second_bytes))
    serve_stream(.reader = $&second_source, .writer = $&second_writer, .handler = $&app)!
    testing.expect(app.calls == 2)!
}

test http_server_failure_after_response := () -> !() {
    request_text: StringView = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
    expected: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello"
    source ::= ByteReader(.bytes = string_bytes(.text = request_text))
    bytes :: [256]UInt8 = zeroed#([256]UInt8)()
    writer ::= ByteWriter(.bytes = view($&bytes))
    app :: _HttpServerTestApp = (.mode = 9, .calls = 0)
    match serve_stream(.reader = $&source, .writer = $&writer, .handler = $&app) {
        ..ok _ { abort } ..error error { testing.expect(error.reason == ..invalid_state)! }
    }
    expected_bytes ::= string_bytes(.text = expected)
    testing.expect(position(&writer).count == length(&expected_bytes).count)!
    i :: UIntNative = 0
    while i < length(&expected_bytes).count {
        testing.expect(bytes[i] == unwrap_or_abort(.value = get(&expected_bytes, .index = i)))!
        i = i + 1
    }
    short_source ::= ByteReader(.bytes = string_bytes(.text = request_text))
    short_bytes :: [10]UInt8 = zeroed#([10]UInt8)()
    short_writer ::= ByteWriter(.bytes = view($&short_bytes))
    short_app :: _HttpServerTestApp = (.mode = 0, .calls = 0)
    match serve_stream(
        .reader = $&short_source, .writer = $&short_writer, .handler = $&short_app
    ) {
        ..ok _ { abort } ..error _ {}
    }
    testing.expect(position(&short_writer).count == 10)!
    testing.expect(short_bytes[0] == 72 and short_bytes[9] == 50)!
}
