main := (.system: System) -> () {

    assume network := system.network
    addresses ::= unwrap_or_abort(
        .value = resolve_addresses(.self = network, .host = "127.0.0.1", .port = 0)
    )
    copy ::= addresses
    length(.self = &copy)
}
