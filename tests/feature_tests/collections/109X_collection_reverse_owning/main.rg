main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: String)(.capacity = 1))
    reverse(.self = $&array)
    deinit(.self = $&array)
}
