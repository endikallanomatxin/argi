main(.system: System) -> !Void = ..ok Void() := {
    assume network := system.network
    match resolve_addresses(.host = "local\0host", .port = 0) {
        ..ok _ { abort } ..error error {
            if [
                error.reason
                != ..invalid_network_argument
            ] { abort }
        }
    }
    addresses ::= resolve_addresses(.host = "localhost", .port = 0, .family = ..ipv4)!
    match get(.self = &addresses, .index = length(.self = &addresses).count) {
        ..ok _ { abort } ..error error { if [
                error.reason
                != ..out_of_bounds
            ] { abort } }
    }
    address ::= get(.self = &addresses, .index = 0)!
    match UdpSocket(.address = address) {
        ..ok _ { abort } ..error error {
            if [
                error.reason
                != ..invalid_network_argument
            ] { abort }
        }
    }
    listener ::= TcpListener(.address = address)!
    bound ::= local_address(.self = &listener)!
    client ::= TcpConnection(.address = bound)!
    connection ::= accept(.self = $&listener)!
    set_timeout(.self = $&connection, .milliseconds = 5000)!
    write_byte(.self = $&client, .byte = 77)!
    flush(.self = $&client)!
    received ::= read_byte(.self = $&connection)!
    match received { ..end { abort } ..ok value { if value != 77 { abort } } }
    close(.self = $&client)!
    match read_byte(.self = $&connection)! { ..end {} ..ok _ { abort } }
    match flush(.self = $&client) { ..ok _ { abort } ..error _ {} }
    match write_byte(.self = $&client, .byte = 77) { ..ok _ { abort } ..error _ {} }
    match local_address(.self = &client) { ..ok _ { abort } ..error _ {} }
    close(.self = $&listener)!
    match accept(.self = $&listener) { ..ok _ { abort } ..error _ {} }
    if port(.self = &bound).value == 0 { abort }
}
