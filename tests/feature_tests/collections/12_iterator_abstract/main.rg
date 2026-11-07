sum_iterator := #(.T: Type: Iterator#(T)) (.it: $&T) -> (.sum: Int32) {

    sum = 0
    while has_next(.self = it) {
        value :: Int32 = next(.self = it)
        sum = sum + value
    }
}

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator
    values: Array#(.n = 3, .t: Int32) = (2, 4, 6)
    array_it ::= to_iterator(.value = &values)
    array_sum :: Int32 = sum_iterator(.it = $&array_it).sum

    dyn :: DynamicArray#(.t: Int32) = unwrap_or_abort(
        .value = DynamicArray#(.t: Int32)(.capacity = 2)
    )
    dyn | push(.self = $&_, .value = 5, .allocator = allocator)
    dyn | push(.self = $&_, .value = 7, .allocator = allocator)
    dynamic_it ::= to_iterator(.value = &dyn)
    dynamic_sum :: Int32 = sum_iterator(.it = $&dynamic_it).sum

    if array_sum != 12 {
        status_code = 1
        return
    }

    if dynamic_sum != 12 {
        status_code = 2
        return
    }

    status_code = 0
}
