-- Run this example, then request http://127.0.0.1:8080/ from a client.
http := import ("network/http")

read_message := (.connection: $&TcpConnection, .head_only: $&Bool) -> (
    .result : Errable#(Void, http.HttpReasons)
) {
    storage :: [4096]UInt8 = zeroed#([4096]UInt8)()
    head_storage :: [8192]UInt8 = zeroed#([8192]UInt8)()
    reader ::= http.HttpReader(.reader = connection, .buffer = view($&storage))
    head ::= http.read_request(.reader = $&reader, .buffer = view($&head_storage))!
    head_only&= http.method_is(.self = &head, .method = "HEAD").ok
    body_reader ::= http.BodyReader(.reader = $&reader, .head = &head)
    scratch :: [4096]UInt8 = zeroed#([4096]UInt8)()
    while http.body_finished(&body_reader).ok == false {
        _ = http.read_body(.self = $&body_reader, .buffer = view($&scratch))!
    }
    result = ..ok Void()
}

serve_connection := (.connection: $&TcpConnection) -> (
    .result : Errable#(Void, http.HttpReasons)
) {
    status :: UInt16 = 200
    head_only ::= false
    match read_message(.connection = connection, .head_only = $&head_only) {
        ..ok _ {}
        ..error error {
            status = 400
            if error.reason == ..body_too_large { status = 413 }
            if error.reason == ..unsupported_expectation { status = 417 }
            if error.reason == ..head_too_large or error.reason == ..too_many_headers {
                status = 431
            }
        }
    }
    body :: StringView = "Hello from Argi!\n"
    if status != 200 { body = "Bad request\n" }
    headers :: [1]http.Header = (
        (
            .name  = string_bytes(.text = "Content-Type")
            .value = string_bytes(.text = "text/plain; charset=utf-8")
        )
    )
    buffer :: [4096]UInt8 = zeroed#([4096]UInt8)()
    writer ::= BufferedWriter#(TcpConnection)(.base = connection, .buffer = view($&buffer))
    http.write_response(
        .writer    = $&writer
        .status    = status
        .headers   = view(&headers)
        .body      = string_bytes(.text = body)
        .head_only = head_only
    )!
    buffered_writer_flush(.self = $&writer)!
    result = ..ok Void()
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    assume network := system.network
    addresses ::= resolve_addresses(
        .self = network, .host = "127.0.0.1", .port = 8080, .family = ..ipv4, .passive = true
    )!!!
    address ::= address_at(.self = &addresses, .index = 0)!!!
    listener ::= TcpListener(.network = network, .address = address)!!!
    while true {
        connection ::= accept(.self = $&listener)!!!
        match set_timeout(.self = $&connection, .milliseconds = 5000) {
            ..ok _ { _ = serve_connection(.connection = $&connection) }
            ..error _ {}
        }
    }
}
