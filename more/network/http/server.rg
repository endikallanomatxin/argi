-- Application state is an ordinary borrowed value. Handler errors are handled
-- at the request boundary; applications choose their own plain error reasons.
Handler#(.App: Type): Contract = (
    .Reasons : Type
    .handle  : (.self: $&App, .request: $&Request) -> (.result: Errable#(Void, Reasons))
)

_ServerOutput#(.Stream: Type): Contract = (
    BlockWriter#(Stream)
    Writer#(Stream)
)

implement#(.Stream: Type) _ServerOutput#(Stream) ()

ServerReasons: Type = choice_union#(
    HttpReasons,
    (
        ..invalid_network_argument,
        ..address_resolution_failed,
        ..socket_open_failed,
        ..socket_accept_failed,
        ..socket_option_failed,
        ..out_of_memory
    )
)

_server_error_status := (.reason: HttpReasons) -> (.status: UInt16 = 400) {
    if reason == ..body_too_large { status = 413 }
    if reason == ..unsupported_expectation { status = 417 }
    if reason == ..head_too_large or reason == ..too_many_headers { status = 431 }
    if reason == ..unsupported_transfer_encoding { status = 501 }
}

_server_error_reply := #(.W: Type: BlockWriter#(W)) (
    .writer: $&W, .status: UInt16, .head_only: Bool = false
) -> (.result: Errable#(Void, HttpReasons) = ..ok Void()) {
    text: StringView = "Request failed\n"
    header: [1]Header = (
        (
            .name  = string_bytes(.text = "Content-Type")
            .value = string_bytes(.text = "text/plain; charset=utf-8")
        )
    )
    write_response(
        .writer    = writer
        .status    = status
        .headers   = view(&header)
        .body      = string_bytes(.text = text)
        .head_only = head_only
    )!
}

-- Serve one message. Streams and application state remain owned by the caller.
-- Defaults are initialized temporary buffers in the caller's lexical scope.
serve_stream := #(
    .R: Type: BlockReader#(R), .W: Type: _ServerOutput#(W), .App: Type: Handler#(App)
) (
    .reader       : $&R,
    .writer       : $&W,
    .handler      : $&App,
    .limits       : Limits                   = Limits(),
    .input_buffer : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)()),
    .head_buffer  : MutableArrayView#(UInt8) = view($&zeroed#([16384]UInt8)()),
    .scratch      : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)())
) -> (.result: Errable#(Void, HttpReasons) = ..ok Void()) {
    buffered ::= HttpReader(.reader = reader, .buffer = input_buffer)
    head ::= read_request(.reader = $&buffered, .buffer = head_buffer) handle error, recovered {
        if error.reason == ..stream_read_failed {
            result = ..error error
            return
        }
        _server_error_reply(
            .writer = writer, .status = _server_error_status(.reason = error.reason).status
        )!
        Writer#().flush(.self = writer)!
        return
    }
    request :: Request = (
        .head                = head
        ._reader             = to_virtual#(.contract: BlockReader)(.value = $&buffered)
        ._writer             = to_virtual#(.contract: BlockWriter)(.value = writer)
        ._flusher            = to_virtual#(.contract: Writer)(.value = writer)
        ._body               = _body_state(.head = &head, .limits = limits)
        ._body_failure       = ..none
        ._response_started   = false
        ._response_finished  = false
        ._response_failed    = false
        ._response_remaining = 0
        ._head_only          = method_is(&head, .method = "HEAD").ok
    )
    failed ::= false
    match Handler#(App).handle(.self = handler, .request = $&request) {
        ..ok _ {}
        ..error _ { failed = true }
    }
    if request._response_started == false {
        status :: UInt16 = 500
        match request._body_failure {
            ..none {}
            ..some failure {
                if failure.value == ..stream_read_failed {
                    result = ..error(.reason = ..stream_read_failed)
                    return
                }
                status = _server_error_status(.reason = failure.value).status
            }
        }
        _server_error_reply(.writer = writer, .status = status, .head_only = request._head_only)!
        Writer#().flush(.self = writer)!
        return
    }
    if request._response_failed or request._response_finished == false {
        result = ..error(.reason = ..invalid_state)
        return
    }
    Writer#().flush(.self = writer)!
    if failed {
        result = ..error(.reason = ..invalid_state)
        return
    }
    -- Publish the response before discarding unread input. This permits clients
    -- to receive an early reply while they are still sending their request.
    if request._body._failed { return }
    while content_finished(&request).ok == false {
        if length(&scratch).count == 0 {
            result = ..error(.reason = ..invalid_stream_buffer)
            return
        }
        _ = read_content(.self = $&request, .buffer = scratch)!
    }
}

-- A caller-owned connection remains open; serve owns and closes each accepted
-- connection after this single-message operation finishes.
serve_connection := #(.App: Type: Handler#(App)) (
    .connection           : $&TcpConnection,
    .handler              : $&App,
    .limits               : Limits                   = Limits(),
    .timeout_milliseconds : UInt32                   = 5000,
    .input_buffer         : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)()),
    .head_buffer          : MutableArrayView#(UInt8) = view($&zeroed#([16384]UInt8)()),
    .output_buffer        : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)()),
    .scratch              : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)())
) -> (.result: Errable#(Void, ServerReasons) = ..ok Void()) {
    set_timeout(.self = connection, .milliseconds = timeout_milliseconds)!
    writer ::= BufferedWriter(.base = connection, .buffer = output_buffer)
    serve_stream(
        .reader       = connection
        .writer       = $&writer
        .handler      = handler
        .limits       = limits
        .input_buffer = input_buffer
        .head_buffer  = head_buffer
        .scratch      = scratch
    )!
}

serve := #(.App: Type: Handler#(App)) (
    .handler              : $&App,
    .network              : &Network,
    .host                 : StringView               = "127.0.0.1",
    .port                 : UInt16                   = 8080,
    .limits               : Limits                   = Limits(),
    .timeout_milliseconds : UInt32                   = 5000,
    .input_buffer         : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)()),
    .head_buffer          : MutableArrayView#(UInt8) = view($&zeroed#([16384]UInt8)()),
    .output_buffer        : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)()),
    .scratch              : MutableArrayView#(UInt8) = view($&zeroed#([4096]UInt8)())
) -> (.result: Errable#(Void, ServerReasons) = ..ok Void()) {
    addresses ::= resolve_addresses(
        .self = network, .host = host, .port = port, .passive = true
    )!
    if length(&addresses).count == 0 {
        result = ..error(.reason = ..address_resolution_failed)
        return
    }
    address ::= unwrap_or_abort(.value = address_at(&addresses, .index = 0))
    listener ::= TcpListener(.network = network, .address = address)!
    while true {
        connection ::= accept(.self = $&listener)!
        -- Per-connection failures must not terminate the listening service.
        _ = serve_connection(
            .connection           = $&connection
            .handler              = handler
            .limits               = limits
            .timeout_milliseconds = timeout_milliseconds
            .input_buffer         = input_buffer
            .head_buffer          = head_buffer
            .output_buffer        = output_buffer
            .scratch              = scratch
        )
    }
}
