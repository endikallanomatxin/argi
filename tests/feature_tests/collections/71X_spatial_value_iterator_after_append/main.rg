main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 4))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    iterator ::= to_iterator#(.t: UIntNative)(.value = &array).iterator
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 8)
    observed ::= next#(.t: UIntNative)(.self = $&iterator).value
    deinit#(.t: UIntNative)(.allocator = system.page_allocator, .self = $&array)
}
