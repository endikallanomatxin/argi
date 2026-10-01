main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap#(.key: Int32, .value: Int32, .policy: Int32HashPolicy)(.policy = Int32HashPolicy(), .allocator = allocator))
    unwrap_or_abort(.value = put(.self = $&map, .key = 1, .value = 1, .allocator = allocator))
    match get_ro_ref(.self = &map, .key = 1).result {
        ..none { abort }
        ..some pointer {
            deinit(.self = $&map, .allocator = allocator)
            if pointer.value& != 1 { abort }
        }
    }
}
