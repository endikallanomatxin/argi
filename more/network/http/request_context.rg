-- One request and its single response. The transport and head
-- storage remain borrowed for the duration of the handler call.
Request := (
    .head                : RequestHead,
    ._reader             : Virtual#(BlockReader),
    ._writer             : Virtual#(BlockWriter),
    ._flusher            : Virtual#(Writer),
    ._body               : _BodyState,
    ._body_failure       : ?HttpReasons,
    ._response_started   : Bool,
    ._response_finished  : Bool,
    ._response_failed    : Bool,
    ._response_remaining : UIntNative,
    ._head_only          : Bool
)

read_content := (.self: $&Request, .buffer: MutableArrayView#(UInt8)) -> (
    .result : Errable#(UIntNative, HttpReasons)
) {
    match _read_body_state#(.R: Virtual#(BlockReader))(
        .reader = $&self&._reader, .state = $&self&._body, .buffer = buffer
    ) {
        ..ok count { result = ..ok count }
        ..error error {
            if is(.value = self&._body_failure, .variant = ..none) {
                self&._body_failure = ..some(.value = error.reason)
            }
            result = ..error error
        }
    }
}

content_finished := (.self: &Request) -> (.ok: Bool) {
    ok = _body_state_finished(.self = &self&._body).ok
}

respond := (
    .self    : $&Request,
    .body    : ArrayView#(UInt8),
    .status  : UInt16             = 200,
    .headers : ArrayView#(Header) = empty_array_view#(Header)().array
) -> (.result: Errable#(Void, HttpReasons)) {
    if self&._response_started or self&._response_failed {
        result = ..error(.reason = ..invalid_state)
        return
    }
    if [
        _response_valid(.status = status, .length = length(&body).count, .headers = headers).ok
        == false
    ] {
        result = ..error(.reason = ..invalid_response)
        return
    }
    self&._response_started = true
    write_response(
        .writer    = $&self&._writer
        .status    = status
        .headers   = headers
        .body      = body
        .head_only = self&._head_only
    ) handle error {
        self&._response_failed = true
        result = ..error error
        return
    }
    self&._response_finished = true
    result = ..ok Void()
}

respond_text := (.self: $&Request, .text: StringView, .status: UInt16 = 200) -> (
    .result : Errable#(Void, HttpReasons)
) {
    headers :: [1]Header = (
        (
            .name  = string_bytes(.text = "Content-Type")
            .value = string_bytes(.text = "text/plain; charset=utf-8")
        )
    )
    result = respond(
        .self    = self
        .body    = string_bytes(.text = text)
        .status  = status
        .headers = view(&headers)
    )
}

begin_reply := (
    .self    : $&Request,
    .length  : UIntNative,
    .status  : UInt16             = 200,
    .headers : ArrayView#(Header) = empty_array_view#(Header)().array
) -> (.result: Errable#(Void, HttpReasons)) {
    if self&._response_started or self&._response_failed {
        result = ..error(.reason = ..invalid_state)
        return
    }
    if [_response_valid(.status = status, .length = length, .headers = headers).ok == false] {
        result = ..error(.reason = ..invalid_response)
        return
    }
    self&._response_started = true
    self&._response_remaining = length
    _http_write_response_head(
        .writer = $&self&._writer, .status = status, .headers = headers, .body_length = length
    ) handle error {
        self&._response_failed = true
        result = ..error error
        return
    }
    result = ..ok Void()
}

write_reply := (.self: $&Request, .body: ArrayView#(UInt8)) -> (
    .result : Errable#(Void, HttpReasons)
) {
    count ::= length(&body).count
    if [
        self&._response_started == false
        or self&._response_finished
        or self&._response_failed
        or count > self&._response_remaining
    ] {
        self&._response_failed = true
        result = ..error(.reason = ..invalid_state)
        return
    }
    if self&._head_only == false {
        write_all(.self = $&self&._writer, .buffer = body) handle error {
            self&._response_failed = true
            match error.reason {
                ..stream_write_failed { result = ..error(.reason = ..stream_write_failed) }
                ..stream_flush_failed { result = ..error(.reason = ..stream_flush_failed) }
            }
            return
        }
    }
    self&._response_remaining = self&._response_remaining - count
    result = ..ok Void()
}

finish_reply := (.self: $&Request) -> (.result: Errable#(Void, HttpReasons)) {
    if [
        self&._response_started == false
        or self&._response_finished
        or self&._response_failed
        or [self&._response_remaining != 0 and self&._head_only == false]
    ] {
        self&._response_failed = true
        result = ..error(.reason = ..invalid_state)
        return
    }
    self&._response_finished = true
    result = ..ok Void()
}

-- Generic stream consumers see a stream error; the specific framing failure
-- remains available through content_failure.
content_failure := (.self: &Request) -> (.reason: ?HttpReasons) {
    reason = self&._body_failure
}

implement BlockReader#(Request) (
    .read_block = (.self: $&Request, .buffer: MutableArrayView#(UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) {
        match read_content(.self = self, .buffer = buffer) {
            ..ok count { result = ..ok count }
            ..error _ { result = ..error(.reason = ..stream_read_failed) }
        }
    }
)

-- Flush explicitly when a streaming reply must reach the transport before the
-- handler returns. A failed flush makes the reply unusable.
flush_reply := (.self: $&Request) -> (.result: Errable#(Void, HttpReasons)) {
    if self&._response_started == false or self&._response_failed {
        result = ..error(.reason = ..invalid_state)
        return
    }
    Writer#().flush(.self = $&self&._flusher) handle error {
        self&._response_failed = true
        match error.reason {
            ..stream_write_failed { result = ..error(.reason = ..stream_write_failed) }
            ..stream_flush_failed { result = ..error(.reason = ..stream_flush_failed) }
        }
        return
    }
    result = ..ok Void()
}
