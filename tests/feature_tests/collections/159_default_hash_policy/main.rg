main := (.system: System) -> () {
    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap<.key: String, .value: Int32>())
    key ::= unwrap_or_abort(.value = format(.value = "key"))
    unwrap_or_abort(.value = put($&map, .key = ~key, .value = 42))
    match get_reference(&map, .key = "key").result {
        ..none { abort }
        ..some item { if item.value&!= 42 { abort } }
    }
}
