_HttpTestSink := (.bytes: MutableArrayView#(UInt8), .position: UIntNative)

implement BlockWriter#(_HttpTestSink) (
    .write_block = (.self: $&_HttpTestSink, .buffer: ArrayView#(UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) {
        if length(&buffer).count == 0 {
            result = ..ok 0
            return
        }
        target ::= unwrap_or_abort(
            .value = get_mutable_reference($&self&.bytes, .index = self&.position)
        )
        target&= unwrap_or_abort(.value = get(&buffer, .index = 0))
        self&.position = self&.position + 1
        result = ..ok 1
    }
)

test http_request_and_response := () -> !() {
    text: StringView = "POST /items HTTP/1.1\r\nHost: example.org\r\nX-Tag: one\r\nx-tag: two\r\nContent-Length: 3\r\n\r\nabcNEXT"
    head ::= unwrap_or_abort(.value = parse_request(.bytes = string_bytes(.text = text)))
    testing.expect([method_is(.self = &head, .method = "POST").ok == false] == false)!
    testing.expect(
        [
            [
                head.header_count != 4
                or length(&head.bytes).count + 7 != byte_length(&text).count
            ]
            == false
        ]
    )!
    match head.framing {
        ..fixed value { testing.expect([value.length != 3] == false)! } ..none { abort } ..chunked {
            abort
        }
    }
    it ::= headers(&head)
    count :: UIntNative = 0
    while true {
        match next($&it).value {
            ..none { break }
            ..some _ { count = count + 1 }
        }
    }
    testing.expect([count != 4] == false)!
    match header(.self = &head, .name = "X-TAG").value {
        ..none { abort }
        ..some item {
            testing.expect(
                [
                    [
                        length(&item.value.value).count != 3
                        or unwrap_or_abort(.value = get(&item.value.value, .index = 0)) != 111
                    ]
                    == false
                ]
            )!
        }
    }
    out :: [256]UInt8 = zeroed#([256]UInt8)()
    sink :: _HttpTestSink = (.bytes = view($&out), .position = 0)
    unwrap_or_abort(
        .value = write_response(.writer = $&sink, .body = string_bytes(.text = "abc"))
    )
    expected: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\nabc"
    bytes ::= string_bytes(.text = expected)
    testing.expect([sink.position != length(&bytes).count] == false)!
    i :: UIntNative = 0
    while i < sink.position {
        testing.expect([out[i] != unwrap_or_abort(.value = get(&bytes, .index = i))] == false)!
        i = i + 1
    }
    sink.position = 0
    unwrap_or_abort(
        .value = write_response(
            .writer = $&sink, .body = string_bytes(.text = "abc"), .head_only = true
        )
    )
    testing.expect([sink.position + 3 != length(&bytes).count] == false)!
    sink.position = 0
    unwrap_or_abort(
        .value = write_response(
            .writer = $&sink, .status = 204, .body = string_bytes(.text = "")
        )
    )
    expected204: StringView = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
    testing.expect([sink.position != byte_length(&expected204).count] == false)!
}

test http_request_forms_and_boundaries := () -> !() {
    wire: StringView = "GET / HTTP/1.1\r\nHost: example\r\n\r\n"
    bytes ::= string_bytes(.text = wire)
    exact ::= parse_request(
        .bytes = bytes, .limits = Limits(.max_head_bytes = length(&bytes).count)
    )!
    testing.expect(exact.version == ..http11)!
    testing.expect_error(
        .expected_reason = ..head_too_large
        .actual_result   = parse_request(
            .bytes = bytes, .limits = Limits(.max_head_bytes = [length(&bytes).count - 1])
        )
    )!
    old ::= parse_request(.bytes = string_bytes(.text = "GET / HTTP/1.0\r\n\r\n"))!
    testing.expect(old.version == ..http10)!
    testing.expect_error(
        .expected_reason = ..invalid_framing
        .actual_result   = parse_request(
            .bytes = string_bytes(
                .text = "POST / HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n"
            )
        )
    )!
    star ::= parse_request(
        .bytes = string_bytes(.text = "OPTIONS * HTTP/1.1\r\nHost: example\r\n\r\n")
    )!
    testing.expect(method_is(&star, .method = "OPTIONS").ok)!
    testing.expect_error(
        .expected_reason = ..invalid_request
        .actual_result   = parse_request(
            .bytes = string_bytes(.text = "GET * HTTP/1.1\r\nHost: example\r\n\r\n")
        )
    )!
    absolute ::= parse_request(
        .bytes = string_bytes(
            .text = "CUSTOM http://example:8080/a%2Fb?x=1 HTTP/1.1\r\nHost: example\r\n\r\n"
        )
    )!
    testing.expect(method_is(&absolute, .method = "CUSTOM").ok)!
    testing.expect_equal_bytes(
        .expected = string_bytes(.text = "http://example:8080/a%2Fb?x=1")
        .actual   = absolute.target
    )!
    testing.expect_error(
        .expected_reason = ..invalid_request
        .actual_result   = parse_request(
            .bytes = string_bytes(
                .text = "CONNECT example:443 HTTP/1.1\r\nHost: example\r\n\r\n"
            )
        )
    )!
    testing.expect_error(
        .expected_reason = ..invalid_request
        .actual_result   = parse_request(
            .bytes = string_bytes(.text = "GET /%GG HTTP/1.1\r\nHost: example\r\n\r\n")
        )
    )!
    ipv6 ::= parse_request(
        .bytes = string_bytes(.text = "GET / HTTP/1.1\r\nHost: [::1]:8080\r\n\r\n")
    )!
    testing.expect(ipv6.header_count == 1)!
    testing.expect_error(
        .expected_reason = ..invalid_header
        .actual_result   = parse_request(
            .bytes = string_bytes(.text = "GET / HTTP/1.1\r\nHost: [1:2:3]\r\n\r\n")
        )
    )!
    testing.expect_error(
        .expected_reason = ..invalid_header
        .actual_result   = parse_request(
            .bytes = string_bytes(.text = "GET / HTTP/1.1\r\nHost: example:65536\r\n\r\n")
        )
    )!
}
