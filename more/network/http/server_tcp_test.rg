_HttpTcpServerApp := (.calls: UIntNative)

implement Handler#(_HttpTcpServerApp) (
    .Reasons : Type = HttpReasons
    .handle  = (.self: $&_HttpTcpServerApp, .request: $&Request) -> (
        .result : Errable#(Void, Reasons)
    ) {
        self&.calls = self&.calls + 1
        result = respond_text(.self = request, .text = "Hello")
    }
)

test http_server_tcp := (.system: System) -> !() {
    assume network := system.network
    addresses ::= resolve_addresses(
        .self = network, .host = "127.0.0.1", .port = 0, .family = ..ipv4, .passive = true
    )!
    address ::= address_at(.self = &addresses, .index = 0)!
    listener ::= TcpListener(.network = network, .address = address)!
    bound ::= local_address(.self = &listener)!
    app :: _HttpTcpServerApp = (.calls = 0)
    iteration :: UIntNative = 0
    while iteration < 2 {
        client ::= TcpConnection(.network = network, .address = bound)!
        set_timeout(.self = $&client, .milliseconds = 5000)!
        wire :: StringView = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        expected :: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello"
        if iteration == 1 {
            wire = "HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n"
            expected = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
        }
        write_all(.self = $&client, .buffer = string_bytes(.text = wire))!
        server ::= accept(.self = $&listener)!
        serve_connection(.connection = $&server, .handler = $&app)!
        testing.expect(is_open(.self = &server).ok)!
        close(.self = $&server)!
        output :: [256]UInt8 = zeroed#([256]UInt8)()
        destination ::= view($&output)
        received :: UIntNative = 0
        while true {
            tail ::= slice(.self = &destination, .start = received, .count = [256 - received])!
            got ::= read(.self = $&client, .buffer = tail)!
            if got == 0 { break }
            received = received + got
            testing.expect(received < 256)!
        }
        expected_bytes ::= string_bytes(.text = expected)
        testing.expect(received == length(&expected_bytes).count)!
        i :: UIntNative = 0
        while i < received {
            testing.expect(
                [output[i] == unwrap_or_abort(.value = get(&expected_bytes, .index = i))]
            )!
            i = i + 1
        }
        close(.self = $&client)!
        iteration = iteration + 1
    }
    testing.expect(app.calls == 2)!
}
