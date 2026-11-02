main := (.system: System) -> () {

    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap#(.key: String, .value: Int32)())
    key ::= unwrap_or_abort(.value = format(.value = "key"))
    get_reference(&map, .key = &key)
}
