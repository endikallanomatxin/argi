main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 4))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    iterator ::= to_iterator(.value = &array).iterator
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 8)
    observed ::= next(.self = $&iterator).value
    deinit( .self = $&array)
}
