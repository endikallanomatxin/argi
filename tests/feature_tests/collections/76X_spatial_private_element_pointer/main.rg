main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 4))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    element ::= _trusted_dynamic_array_element_ro_pointer#(.t: UIntNative)(.array = &array, .offset = 0).pointer
    
    observed ::= element&
    deinit#(.t: UIntNative)(.allocator = system.page_allocator, .self = $&array)
}
