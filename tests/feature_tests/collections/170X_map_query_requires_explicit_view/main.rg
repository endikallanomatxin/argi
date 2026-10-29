main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap#(.key: String, .value: Int32)())
    key ::= unwrap_or_abort(.value = format(.value = "key"))
    get_reference(&map, .key = &key)
}
