test http_tcp_loopback := (.system: System) -> !() {
    assume writer ::= $&system.terminal&.stderr
    assume network := system.network
    addresses ::= resolve_addresses(
        .self = network, .host = "127.0.0.1", .port = 0, .family = ..ipv4, .passive = true
    )!
    address ::= address_at(.self = &addresses, .index = 0)!
    listener ::= TcpListener(.network = network, .address = address)!
    bound ::= local_address(.self = &listener)!
    client ::= TcpConnection(.network = network, .address = bound)!
    server ::= accept(.self = $&listener)!
    set_timeout(.self = $&client, .milliseconds = 5000)!
    set_timeout(.self = $&server, .milliseconds = 5000)!
    request: StringView = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 3\r\n\r\nabc"
    write_all(.self = $&client, .buffer = string_bytes(.text = request))!
    {
        read_storage :: [128]UInt8 = zeroed#([128]UInt8)()
        head_storage :: [128]UInt8 = zeroed#([128]UInt8)()
        reader ::= HttpReader#(TcpConnection)(
            .reader = $&server, .buffer = view($&read_storage)
        )
        head ::= read_request(.reader = $&reader, .buffer = view($&head_storage))!
        testing.expect(method_is(.self = &head, .method = "POST").ok)!
        state ::= _body_state(.head = &head)
        body :: [3]UInt8 = zeroed#([3]UInt8)()
        count :: UIntNative = 0
        body_view ::= view($&body)
        while count < 3 {
            tail ::= slice(.self = &body_view, .start = count, .count = [3 - count])!
            got ::= _read_body_state(.reader = $&reader, .state = $&state, .buffer = tail)!
            if got == 0 { abort }
            count = count + got
        }
        if body[0] != 97 or body[1] != 98 or body[2] != 99 { abort }
        testing.expect(_body_state_finished(&state).ok)!
    }
    write_response(.writer = $&server, .body = string_bytes(.text = "ok"))!
    shutdown_write(.self = $&server)!
    expected: StringView = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 2\r\n\r\nok"
    expected_bytes ::= string_bytes(.text = expected)
    output :: [128]UInt8 = zeroed#([128]UInt8)()
    destination ::= view($&output)
    received :: UIntNative = 0
    while true {
        tail ::= slice(.self = &destination, .start = received, .count = [128 - received])!
        got ::= read(.self = $&client, .buffer = tail)!
        if got == 0 { break }
        received = received + got
        if received == 128 { abort }
    }
    testing.expect(received == length(&expected_bytes).count)!
    i :: UIntNative = 0
    while i < received {
        testing.expect(output[i] == unwrap_or_abort(.value = get(&expected_bytes, .index = i)))!
        i = i + 1
    }
}
