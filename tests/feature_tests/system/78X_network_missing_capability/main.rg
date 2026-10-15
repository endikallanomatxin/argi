main() -> () := {
    addresses ::= unwrap_or_abort(.value = resolve_addresses(.host = "127.0.0.1", .port = 0))
}
