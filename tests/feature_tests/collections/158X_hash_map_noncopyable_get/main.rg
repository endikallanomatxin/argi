main := (.system: System) -> () {
    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(
        .value = HashMap<.key: Int32, .value: String, .policy: StandardHashPolicy>(
            .policy = StandardHashPolicy()
        )
    )
    query: Int32 = 1
    _ ::= get(&map, .key = &query)
}
