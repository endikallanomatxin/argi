test http_body_reader := () -> !() {
    request: StringView = "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
    head ::= unwrap_or_abort(.value = parse_request(.bytes = string_bytes(.text = request)))
    wire: StringView = "2\r\nab\r\n1\r\nc\r\n0\r\nX-End: yes\r\n\r\nNEXT"
    source ::= ByteReader(.bytes = string_bytes(.text = wire))
    body ::= BodyReader#(ByteReader)(.reader = $&source, .head = &head)
    empty :: [0]UInt8 = ()
    testing.expect(
        [
            [
                unwrap_or_abort(.value = read_body(.self = $&body, .buffer = view($&empty)))
                != 0
            ]
            == false
        ]
    )!
    testing.expect([position(&source).count != 0] == false)!
    output :: [3]UInt8 = (0, 0, 0)
    writer ::= ByteWriter(.bytes = view($&output))
    scratch :: [2]UInt8 = (0, 0)
    copied ::= unwrap_or_abort(
        .value = copy_stream(.reader = $&body, .writer = $&writer, .buffer = view($&scratch))
    )
    testing.expect(
        [[copied != 3 or output[0] != 97 or output[1] != 98 or output[2] != 99] == false]
    )!
    testing.expect([body_finished(&body).ok == false] == false)!
    match body_failure(&body).reason { ..none {} ..some _ { abort } }
    match unwrap_or_abort(.value = Reader#().read_byte($&source)) {
        ..end { abort }
        ..ok byte { testing.expect([byte != 78] == false)! }
    }

    fixed_request: StringView = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\n"
    fixed_head ::= unwrap_or_abort(
        .value = parse_request(.bytes = string_bytes(.text = fixed_request))
    )
    fixed_source ::= ByteReader(.bytes = string_bytes(.text = "xyz!"))
    fixed ::= BodyReader#(ByteReader)(.reader = $&fixed_source, .head = &fixed_head)
    fixed_output :: [3]UInt8 = (0, 0, 0)
    unwrap_or_abort(.value = read_exact(.self = $&fixed, .buffer = view($&fixed_output)))
    testing.expect(
        [
            [
                fixed_output[0] != 120
                or fixed_output[2] != 122
                or body_finished(&fixed).ok == false
            ]
            == false
        ]
    )!

    bad_source ::= ByteReader(.bytes = string_bytes(.text = "z\r\n"))
    bad ::= BodyReader#(ByteReader)(.reader = $&bad_source, .head = &head)
    match BlockReader#().read_block($&bad, .buffer = view($&scratch)) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..stream_read_failed] == false)! }
    }
    match body_failure(&bad).reason {
        ..none { abort }
        ..some item { testing.expect([item.value != ..invalid_chunk] == false)! }
    }
    match BlockReader#().read_block($&bad, .buffer = view($&scratch)) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..stream_read_failed] == false)! }
    }
    match body_failure(&bad).reason {
        ..none { abort }
        ..some item { testing.expect([item.value != ..invalid_chunk] == false)! }
    }

    limited_source ::= ByteReader(.bytes = string_bytes(.text = "4\r\n"))
    limited ::= BodyReader#(ByteReader)(
        .reader = $&limited_source, .head = &head, .limits = Limits(.max_body_bytes = 3)
    )
    match read_body(.self = $&limited, .buffer = view($&scratch)) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..body_too_large] == false)! }
    }
}
