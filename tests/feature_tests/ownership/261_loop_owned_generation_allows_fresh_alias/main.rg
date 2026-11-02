unsafe_allocation := import ("../../_support/unsafe_allocation")

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    buffer ::= unwrap_or_abort(
        .value = string_with_capacity(.allocator = allocator, .capacity = 1)
    )
    first ::= push_ascii(.self = $&buffer, .byte = 65, .allocator = allocator)
    if is(.value = first, .variant = ..error) {
        return
    }
    i :: UIntNative = 0
    while i < 1 {
        pushed ::= push_ascii(.self = $&buffer, .byte = 66, .allocator = allocator)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    fresh_data ::= unwrap_or_abort(
        .value = string_byte_reference(.string = &buffer, .index = 0)
    )
    if fresh_data&!= 65 {
        status_code = 2
        return
    }
    deinit(.self = $&buffer)
}
