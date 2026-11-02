_HttpResponseTestSink := (
    .bytes    : MutableArrayView#(UInt8),
    .position : UIntNative,
    .fail_at  : UIntNative
)

implement BlockWriter#(_HttpResponseTestSink) (
    .write_block = (.self: $&_HttpResponseTestSink, .buffer: ArrayView#(UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) {
        if self&.position >= self&.fail_at {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
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

test http_response_stream := () -> !() {
    output :: [256]UInt8 = zeroed#([256]UInt8)()
    sink :: _HttpResponseTestSink = (.bytes = view($&output), .position = 0, .fail_at = 256)
    {
        response ::= unwrap_or_abort(.value = begin_response(.writer = $&sink, .length = 3))
        unwrap_or_abort(
            .value = write_body(.self = $&response, .body = string_bytes(.text = "a"))
        )
        unwrap_or_abort(
            .value = write_body(.self = $&response, .body = string_bytes(.text = "bc"))
        )
        unwrap_or_abort(.value = finish_response(.self = $&response))
        match finish_response(.self = $&response) {
            ..ok _ { abort } ..error e { if [e.reason != ..invalid_state] { abort } }
        }
    }
    expected: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\nabc"
    bytes ::= string_bytes(.text = expected)
    testing.expect(sink.position == length(&bytes).count)!
    i :: UIntNative = 0
    while i < sink.position {
        testing.expect(output[i] == unwrap_or_abort(.value = get(&bytes, .index = i)))!
        i = i + 1
    }
    sink.position = 0
    {
        response ::= unwrap_or_abort(.value = begin_response(.writer = $&sink, .length = 1))
        match write_body(.self = $&response, .body = string_bytes(.text = "ab")) {
            ..ok _ { abort } ..error e { if [e.reason != ..invalid_state] { abort } }
        }
        match finish_response(.self = $&response) {
            ..ok _ { abort } ..error e { if [e.reason != ..invalid_state] { abort } }
        }
    }
    sink.position = 0
    {
        response ::= unwrap_or_abort(.value = begin_response(.writer = $&sink, .length = 1))
        match finish_response(.self = $&response) {
            ..ok _ { abort } ..error e { if [e.reason != ..invalid_state] { abort } }
        }
    }
    sink.position = 0
    {
        response ::= unwrap_or_abort(
            .value = begin_response(.writer = $&sink, .length = 3, .head_only = true)
        )
        unwrap_or_abort(.value = finish_response(.self = $&response))
    }
    testing.expect(sink.position + 3 == length(&bytes).count)!
    sink.position = 0
    match begin_response(.writer = $&sink, .length = 0, .status = 100) {
        ..ok _ { abort } ..error e { if [e.reason != ..invalid_response] { abort } }
    }
    testing.expect(sink.position == 0)!
    match write_response(.writer = $&sink, .status = 205, .body = string_bytes(.text = "x")) {
        ..ok _ { abort } ..error e { if [e.reason != ..invalid_response] { abort } }
    }
    testing.expect(sink.position == 0)!
    sink.fail_at = length(&bytes).count - 3
    {
        response ::= unwrap_or_abort(.value = begin_response(.writer = $&sink, .length = 1))
        match write_body(.self = $&response, .body = string_bytes(.text = "x")) {
            ..ok _ { abort } ..error e { if [e.reason != ..stream_write_failed] { abort } }
        }
        match finish_response(.self = $&response) {
            ..ok _ { abort } ..error e { if [e.reason != ..invalid_state] { abort } }
        }
    }
}
