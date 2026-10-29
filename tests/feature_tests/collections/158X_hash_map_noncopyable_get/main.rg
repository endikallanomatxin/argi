main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(
        .value = HashMap#(.key: Int32, .value: String, .policy: StandardHashPolicy)(
            .policy = StandardHashPolicy()
        )
    )
    query: Int32 = 1
    _ ::= get(&map, .key = &query)
}
