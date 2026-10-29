main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume network := system.network
    addresses ::= unwrap_or_abort(
        .value = resolve_addresses(.self = network, .host = "127.0.0.1", .port = 0)
    )
    deinit(.self = $&addresses)
    length(.self = &addresses)
}
