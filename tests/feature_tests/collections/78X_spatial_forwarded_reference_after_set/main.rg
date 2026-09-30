replace(.array: $&DynamicArray#(.t: UIntNative), .allocator: $&Allocator) -> () := {
    replaced ::= set#(.t: UIntNative)(.self = array, .index = 0, .value = 9, .allocator = allocator).result
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 2))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    element ::= unwrap_or_abort(.value = get_rw_ref#(.t: UIntNative)(.self = $&array, .index = 0).result)
    replace(.array = $&array, .allocator = system.page_allocator)
    element& = 11
    abort
}
