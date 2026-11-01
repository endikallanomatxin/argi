_HttpTestStalled := (.calls: UIntNative)

implement BlockWriter#(_HttpTestStalled) (
    .write_block = (.self: $&_HttpTestStalled, .buffer: ArrayView#(UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) {
        self&.calls = self&.calls + 1
        result = ..ok 0
    }
)

_http_test_reject := (.text: StringView, .reason: HttpReasons) -> () {
    match parse_request(.bytes = string_bytes(.text = text)) {
        ..ok _ { abort }
        ..error error { if error.reason != reason { abort } }
    }
}

test http_rejections := () -> !() {
    _http_test_reject(.text = "GET / HTTP/1.1\r\n\r\n", .reason = ..invalid_header)
    _http_test_reject(.text = "GET / HTTP/1.1\nHost: x\n\n", .reason = ..invalid_request)
    _http_test_reject(
        .text = "GET / HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n", .reason = ..invalid_header
    )
    _http_test_reject(
        .text   = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\n"
        .reason = ..invalid_framing
    )
    _http_test_reject(
        .text   = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n"
        .reason = ..invalid_framing
    )
    _http_test_reject(
        .text   = "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n"
        .reason = ..unsupported_transfer_encoding
    )
    _http_test_reject(
        .text   = "GET / HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\n\r\n"
        .reason = ..unsupported_expectation
    )
    _http_test_reject(.text = "GET / HTTP/1.1\r\nHost: x\r\n", .reason = ..unexpected_eof)
    match parse_request(
        .bytes  = string_bytes(.text = "GET / HTTP/1.1\r\nHost: x\r\n\r\n")
        .limits = Limits(.max_headers = 0)
    ) {
        ..ok _ { abort } ..error error {
            testing.expect([[error.reason != ..too_many_headers] == false])!
        }
    }
    match parse_request(
        .bytes = string_bytes(
            .text = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 4\r\n\r\n"
        )
        .limits = Limits(.max_body_bytes = 3)
    ) {
        ..ok _ { abort } ..error error {
            testing.expect([[error.reason != ..body_too_large] == false])!
        }
    }
    stalled :: _HttpTestStalled = (.calls = 0)
    invalid_headers: [2]Header = (
        (
            .name  = string_bytes(.text = "X-Good")
            .value = string_bytes(.text = "ok\r\nInjected: yes")
        ),
        (.name = string_bytes(.text = "Content-Length"), .value = string_bytes(.text = "999"))
    )
    headers ::= view(&invalid_headers)
    match write_response(
        .writer = $&stalled, .body = string_bytes(.text = ""), .headers = headers
    ) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..invalid_response] == false)! }
    }
    testing.expect([stalled.calls != 0] == false)!
    framing_header ::= unwrap_or_abort(.value = slice(&headers, .start = 1, .count = 1))
    match write_response(
        .writer = $&stalled, .body = string_bytes(.text = ""), .headers = framing_header
    ) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..invalid_response] == false)! }
    }
    testing.expect([stalled.calls != 0] == false)!
    match write_response(.writer = $&stalled, .body = string_bytes(.text = "ok")) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..stream_write_failed] == false)! }
    }
    testing.expect([stalled.calls != 1] == false)!

}
