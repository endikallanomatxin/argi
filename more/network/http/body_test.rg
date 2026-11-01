_HttpTestSource := (.bytes: ArrayView#(UInt8), .position: UIntNative, .calls: UIntNative)

implement BlockReader#(_HttpTestSource) (
    .read_block = (.self: $&_HttpTestSource, .buffer: MutableArrayView#(UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {
        self&.calls = self&.calls + 1
        if length(&buffer).count == 0 or self&.position == length(&self&.bytes).count {
            result = ..ok 0
            return
        }
        byte ::= unwrap_or_abort(.value = get(&self&.bytes, .index = self&.position))
        dest ::= unwrap_or_abort(.value = get_mutable_reference($&buffer, .index = 0))
        dest&= byte
        self&.position = self&.position + 1
        result = ..ok 1
    }
)

_http_test_check_body_error := (
    .body: StringView, .reason: HttpReasons, .limits: Limits = Limits()
) -> () {
    request: StringView = "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
    head ::= unwrap_or_abort(.value = parse_request(.bytes = string_bytes(.text = request)))
    state ::= _body_state(.head = &head, .limits = limits)
    source :: _HttpTestSource = (
        .bytes    = string_bytes(.text = body)
        .position = 0
        .calls    = 0
    )
    output :: [8]UInt8 = zeroed#([8]UInt8)()
    while true {
        match _read_body_state(.reader = $&source, .state = $&state, .buffer = view($&output)) {
            ..ok count { if count == 0 { abort } }
            ..error error {
                if error.reason != reason { abort }
                break
            }
        }
    }
    calls ::= source.calls
    match _read_body_state(.reader = $&source, .state = $&state, .buffer = view($&output)) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_state { abort } }
    }
    if source.calls != calls { abort }
}

test http_body_streams := () -> !() {
    wire: StringView = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nabcNEXT"
    source :: _HttpTestSource = (
        .bytes    = string_bytes(.text = wire)
        .position = 0
        .calls    = 0
    )
    storage :: [16]UInt8 = zeroed#([16]UInt8)()
    reader ::= HttpReader#(_HttpTestSource)(.reader = $&source, .buffer = view($&storage))
    head_bytes :: [128]UInt8 = zeroed#([128]UInt8)()
    head ::= unwrap_or_abort(
        .value = read_request(.reader = $&reader, .buffer = view($&head_bytes))
    )
    state ::= _body_state(.head = &head)
    output :: [4]UInt8 = zeroed#([4]UInt8)()
    empty :: [0]UInt8 = ()
    calls ::= source.calls
    testing.expect(
        [
            [
                unwrap_or_abort(
                    .value = _read_body_state(
                        .reader = $&reader, .state = $&state, .buffer = view($&empty)
                    )
                )
                != 0
            ]
            == false
        ]
    )!
    testing.expect([source.calls != calls] == false)!
    i :: UIntNative = 0
    while i < 3 {
        testing.expect(
            [
                [
                    unwrap_or_abort(
                        .value = _read_body_state(
                            .reader = $&reader, .state = $&state, .buffer = view($&output)
                        )
                    )
                    != 1
                ]
                == false
            ]
        )!
        testing.expect(
            [
                [
                    output[0]
                    != unwrap_or_abort(.value = [[97 + i] | convert#(.to: UInt8)(_)])
                ]
                == false
            ]
        )!
        i = i + 1
    }
    testing.expect([_body_state_finished(&state).ok == false] == false)!
    testing.expect(
        [
            [
                unwrap_or_abort(
                    .value = _read_body_state(
                        .reader = $&reader, .state = $&state, .buffer = view($&output)
                    )
                )
                != 0
            ]
            == false
        ]
    )!
    testing.expect(
        [
            [
                [
                    unwrap_or_abort(
                        .value = BlockReader#().read_block($&reader, .buffer = view($&output))
                    )
                    != 1
                ]
                or output[0] != 78
            ]
            == false
        ]
    )!

    -- A block reader can prefetch beyond the head; the adapter retains those bytes.
    prefetch_wire: StringView = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nabcNEXT"
    block_source ::= ByteReader(.bytes = string_bytes(.text = prefetch_wire))
    prefetch_storage :: [128]UInt8 = zeroed#([128]UInt8)()
    buffered ::= HttpReader#(ByteReader)(
        .reader = $&block_source, .buffer = view($&prefetch_storage)
    )
    prefetch_head_storage :: [128]UInt8 = zeroed#([128]UInt8)()
    prefetch_head ::= unwrap_or_abort(
        .value = read_request(.reader = $&buffered, .buffer = view($&prefetch_head_storage))
    )
    prefetch_state ::= _body_state(.head = &prefetch_head)
    testing.expect(
        [
            [
                unwrap_or_abort(
                    .value = _read_body_state(
                        .reader = $&buffered
                        .state  = $&prefetch_state
                        .buffer = view($&output)
                    )
                )
                != 3
            ]
            == false
        ]
    )!
    testing.expect([output[0] != 97 or output[1] != 98 or output[2] != 99] == false)!
    testing.expect(
        [
            [
                unwrap_or_abort(
                    .value = BlockReader#().read_block($&buffered, .buffer = view($&output))
                )
                != 4
            ]
            == false
        ]
    )!
    testing.expect([output[0] != 78 or output[3] != 84] == false)!

    chunked: StringView = "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
    chunk_head ::= unwrap_or_abort(
        .value = parse_request(.bytes = string_bytes(.text = chunked))
    )
    chunk_state ::= _body_state(.head = &chunk_head)
    chunks: StringView = "2;foo=\"bar\"\r\nab\r\n1\r\nc\r\n0\r\nX-End: yes\r\n\r\nNEXT"
    chunk_source :: _HttpTestSource = (
        .bytes    = string_bytes(.text = chunks)
        .position = 0
        .calls    = 0
    )
    i = 0
    while true {
        count ::= unwrap_or_abort(
            .value = _read_body_state(
                .reader = $&chunk_source, .state = $&chunk_state, .buffer = view($&output)
            )
        )
        if count == 0 { break }
        testing.expect(
            [
                [
                    count != 1
                    or [
                        output[0]
                        != unwrap_or_abort(.value = [[97 + i] | convert#(.to: UInt8)(_)])
                    ]
                ]
                == false
            ]
        )!
        i = i + 1
    }
    testing.expect([i != 3 or _body_state_finished(&chunk_state).ok == false] == false)!
    testing.expect(
        [
            [
                [
                    unwrap_or_abort(
                        .value = BlockReader#(
                        ).read_block($&chunk_source, .buffer = view($&output))
                    )
                    != 1
                ]
                or output[0] != 78
            ]
            == false
        ]
    )!
    _http_test_check_body_error(.body = "z\r\n", .reason = ..invalid_chunk)
    _http_test_check_body_error(.body = "2\r\na", .reason = ..unexpected_eof)
    _http_test_check_body_error(.body = "0\r\nHost: evil\r\n\r\n", .reason = ..invalid_header)
    _http_test_check_body_error(
        .body = "4\r\n", .reason = ..body_too_large, .limits = Limits(.max_body_bytes = 3)
    )
    _http_test_check_body_error(
        .body   = "1;foo=bar\r\na\r\n0\r\n\r\n"
        .reason = ..invalid_chunk
        .limits = Limits(.max_chunk_line_bytes = 4)
    )
    _http_test_check_body_error(.body = "1 \r\na\r\n0\r\n\r\n", .reason = ..invalid_chunk)
    _http_test_check_body_error(.body = "1;name=\r\na\r\n", .reason = ..invalid_chunk)
    _http_test_check_body_error(.body = "1;=value\r\na\r\n", .reason = ..invalid_chunk)
    _http_test_check_body_error(
        .body = "1;name=\"unterminated\r\na\r\n", .reason = ..invalid_chunk
    )
    _http_test_check_body_error(
        .body   = "0\r\nX-A: 1\r\n\r\n"
        .reason = ..head_too_large
        .limits = Limits(.max_trailer_bytes = 5)
    )
    _http_test_check_body_error(
        .body   = "0\r\nX-A: 1\r\nX-B: 2\r\n\r\n"
        .reason = ..too_many_headers
        .limits = Limits(.max_headers = 1)
    )
    _http_test_check_body_error(
        .body   = "2\r\nab\r\n2\r\ncd\r\n0\r\n\r\n"
        .reason = ..body_too_large
        .limits = Limits(.max_body_bytes = 3)
    )
    fixed_text: StringView = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n"
    fixed_head ::= unwrap_or_abort(
        .value = parse_request(.bytes = string_bytes(.text = fixed_text))
    )
    fixed_state ::= _body_state(.head = &fixed_head)
    fixed_source :: _HttpTestSource = (
        .bytes    = string_bytes(.text = "a")
        .position = 0
        .calls    = 0
    )
    testing.expect(
        [
            [
                unwrap_or_abort(
                    .value = _read_body_state(
                        .reader = $&fixed_source
                        .state  = $&fixed_state
                        .buffer = view($&output)
                    )
                )
                != 1
            ]
            == false
        ]
    )!
    match _read_body_state(
        .reader = $&fixed_source, .state = $&fixed_state, .buffer = view($&output)
    ) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..unexpected_eof] == false)! }
    }

}
