main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 4))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    iterator ::= to_ro_pointer_iterator#(.t: UIntNative)(.value = &array).iterator
    element ::= next#(.t: UIntNative)(.self = $&iterator).value
    removed ::= unwrap_or_abort(.value = pop#(.t: UIntNative)(.self = $&array).result)
    observed ::= element&
    deinit#(.t: UIntNative)(.allocator = system.page_allocator, .self = $&array)
}
