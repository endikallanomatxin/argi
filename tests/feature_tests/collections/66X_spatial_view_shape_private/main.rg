main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 2))
    array._shape = (.marker = 0)
    deinit#(.t: UIntNative)(.allocator = system.page_allocator, .self = $&array)
}
