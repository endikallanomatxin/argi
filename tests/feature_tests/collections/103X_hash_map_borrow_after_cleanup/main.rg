main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    map ::= unwrap_or_abort(
        .value = HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
            .policy = StandardHashPolicy(), .allocator = allocator
        )
    )
    unwrap_or_abort(.value = put(.self = $&map, .key = 1, .value = 1, .allocator = allocator))
    match get_reference(.self = &map, .key = &1).result {
        ..none { abort }
        ..some pointer {
            deinit(.self = $&map)
            if pointer.value&!= 1 { abort }
        }
    }
}
