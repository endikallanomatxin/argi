make := (
    .allocator: $&Virtual#(Allocator), .value: &Int32
) -> (.result: DynamicArray#(&Int32)) {

    assume allocator
    array ::= unwrap_or_abort(DynamicArray#(&Int32)(.capacity = 1))

    push_assume_capacity($&array, value)
    result = ~array
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_concrete := $&GeneralPurposeAllocator(system.page_allocator)

    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)

    assume allocator := $&virtual_allocator
    local :: Int32 = 7
    array ::= make(allocator, &local)
    reference ::= unwrap_or_abort(get_reference(&array, .index = 0))

    if reference&&!= 7 { status_code = 1 }
}
