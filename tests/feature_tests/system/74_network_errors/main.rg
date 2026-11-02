main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    assume network := system.network
    match resolve_addresses(.self = network, .host = "local\0host", .port = 0) {
        ..ok _ { abort } ..error error {
            if [error.reason != ..invalid_network_argument] { abort }
        }
    }
    addresses ::= resolve_addresses(
        .self = network, .host = "localhost", .port = 0, .family = ..ipv4
    )!!!
    match address_at(.self = &addresses, .index = length(.self = &addresses).count) {
        ..ok _ { abort } ..error error { if [error.reason != ..out_of_bounds] { abort } }
    }
    address ::= address_at(.self = &addresses, .index = 0)!!!
    match UdpSocket(.network = network, .address = address) {
        ..ok _ { abort } ..error error {
            if [error.reason != ..invalid_network_argument] { abort }
        }
    }
    listener ::= TcpListener(.network = network, .address = address)!!!
    bound ::= local_address(.self = &listener)!!!
    client ::= TcpConnection(.network = network, .address = bound)!!!
    connection ::= accept(.self = $&listener)!!!
    set_timeout(.self = $&connection, .milliseconds = 5000)!!!
    Writer#().write_byte(.self = $&client, .byte = 77)!!!
    Writer#().flush(.self = $&client)!!!
    received ::= Reader#().read_byte(.self = $&connection)!!!
    match received { ..end { abort } ..ok value { if value != 77 { abort } } }
    close(.self = $&client)!!!
    match Reader#().read_byte(.self = $&connection)!!! { ..end {} ..ok _ { abort } }
    match Writer#().flush(.self = $&client) { ..ok _ { abort } ..error _ {} }
    match Writer#().write_byte(.self = $&client, .byte = 77) { ..ok _ { abort } ..error _ {} }
    match local_address(.self = &client) { ..ok _ { abort } ..error _ {} }
    close(.self = $&listener)!!!
    match accept(.self = $&listener) { ..ok _ { abort } ..error _ {} }
    if port(.self = &bound).value == 0 { abort }
    status_code = 0
}
