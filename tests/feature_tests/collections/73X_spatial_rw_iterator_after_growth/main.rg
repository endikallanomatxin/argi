main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 4))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    iterator ::= to_rw_pointer_iterator(.value = $&array).iterator
    unwrap_or_abort(.value = ensure_capacity(.allocator = system.page_allocator, .self = $&array, .capacity = 8).result)
    element ::= next(.self = $&iterator).value
    element& = 3
    deinit( .self = $&array)
}
