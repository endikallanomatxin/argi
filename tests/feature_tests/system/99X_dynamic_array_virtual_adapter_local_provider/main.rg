grow_with_local := (
    .backing: Virtual#(Allocator), .array: $&DynamicArray#(Int32)
) -> () {
    local ::= GeneralPurposeAllocator(backing)
    virtual ::= to_virtual#(Allocator)($&local)
    unwrap_or_abort(ensure_capacity(.allocator = virtual, .self = array, .capacity = 64))
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator ::= GeneralPurposeAllocator(system.page_allocator)
    handle ::= to_virtual#(Allocator)($&allocator)
    array ::= unwrap_or_abort(DynamicArray#(Int32)(.allocator = handle, .capacity = 1))
    unwrap_or_abort(push(.allocator = handle, .self = $&array, .value = 42))
    grow_with_local(.backing = system.page_allocator, .array = $&array)
    if unwrap_or_abort(get_reference(&array, .index = 0))&!= 42 { abort }
}
