escape := (.array: $&DynamicArray#(&Int32)) -> () {
    local :: Int32 = 7
    push_assume_capacity(array, &local)
}

main := (.system: System) -> () {

    allocator_concrete := $&GeneralPurposeAllocator(system.page_allocator)

    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)

    assume allocator := virtual_allocator
    array ::= unwrap_or_abort(DynamicArray#(&Int32)(.capacity = 1))
    escape($&array)
    reference ::= unwrap_or_abort(get_reference(&array, .index = 0))
    if reference&& != 7 { abort }
}
