main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator
    dyn :: DynamicArray#(.t: Int32) = unwrap_or_abort(
        .value = DynamicArray#(.t: Int32)(.capacity = 2)
    )
    defer deinit(.self = $&dyn)

    push(.self = $&dyn, .value = 10, .allocator = allocator)
    push(.self = $&dyn, .value = 20, .allocator = allocator)
    push(.self = $&dyn, .value = 30, .allocator = allocator)

    it ::= to_iterator(.value = &dyn)
    sum :: Int32 = 0

    while has_next(.self = &it) {
        value :: Int32 = next(.self = $&it)
        sum = sum + value
    }

    if sum != 60 {
        status_code = 1
        return
    }

    status_code = 0
}
