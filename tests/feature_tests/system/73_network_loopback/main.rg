run_main(.system: System) -> !Void = ..ok Void() := {
    assume network := system.network
    addresses ::= resolve_addresses(
        .host    = "127.0.0.1"
        .port    = 0
        .family  = ..ipv4
        .passive = true
    )!
    if length(.self = &addresses).count == 0 { abort }
    address ::= get(.self = &addresses, .index = 0)!
    listener ::= TcpListener(.address = address)!
    bound ::= local_address(.self = &listener)!
    if port(.self = &bound).value == 0 { abort }
    client ::= TcpConnection(.address = bound)!
    server ::= accept(.self = $&listener)!
    set_timeout(.self = $&client, .milliseconds = 5000)!
    set_timeout(.self = $&server, .milliseconds = 5000)!
    bytes: [4]UInt8 = (65, 0, 66, 67)
    input ::= view(.array = &bytes)
    sent :: UIntNative = 0
    while sent < 4 {
        remaining ::= slice(.self = &input, .start = sent, .count = 4 - sent)!
        count ::= write(.self = $&client, .buffer = remaining)!
        if count == 0 { abort }
        sent = sent + count
    }
    shutdown_write(.self = $&client)!
    output :: [4]UInt8 = (0, 0, 0, 0)
    destination ::= view(.array = $&output)
    received :: UIntNative = 0
    while received < 4 {
        remaining ::= slice(.self = &destination, .start = received, .count = 4 - received)!
        count ::= read(.self = $&server, .buffer = remaining)!
        if count == 0 { abort }
        received = received + count
    }
    if output[0] != 65 or output[1] != 0 or output[2] != 66 or output[3] != 67 { abort }
    if read(.self = $&server, .buffer = destination)! != 0 { abort }
    close(.self = $&server)!
    close(.self = $&server)!
    if is_open(.self = &server).value { abort }

    udp_addresses ::= resolve_addresses(
        .host      = "127.0.0.1"
        .port      = 0
        .transport = ..udp
        .family    = ..ipv4
    )!
    udp_address ::= get(.self = &udp_addresses, .index = 0)!
    receiver ::= UdpSocket(.address = udp_address)!
    sender ::= UdpSocket(.address = udp_address)!
    set_timeout(.self = $&receiver, .milliseconds = 5000)!
    peer ::= local_address(.self = &receiver)!
    if send_to(.self = $&sender, .peer = peer, .buffer = input)! != 4 { abort }
    datagram ::= receive_from(.self = $&receiver, .buffer = destination)!
    if datagram.count != 4 or output[0] != 65 or output[2] != 66 { abort }
    empty ::= array_view_ro#(.t: UInt8)()
    if send_to(.self = $&sender, .peer = peer, .buffer = empty)! != 0 { abort }
    if receive_from(.self = $&receiver, .buffer = destination)!.count != 0 { abort }
    _ = send_to(.self = $&sender, .peer = peer, .buffer = input)!
    small ::= slice(.self = &destination, .start = 0, .count = 1)!
    match receive_from(.self = $&receiver, .buffer = small) {
        ..ok _ { abort }
        ..error error {
            if is(.value = error.reason, .variant = ..datagram_truncated) == false { abort }
        }
    }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
