unsafe_allocation := import ("../../_support/unsafe_allocation")

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    i :: UIntNative = 0
    while i < 2 {
        local ::= unwrap_or_abort(
            .value = string_with_capacity(.allocator = allocator, .capacity = 1)
        )
        pushed ::= push_ascii(.self = $&local, .byte = 65, .allocator = allocator)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        data ::= unwrap_or_abort(.value = string_byte_reference(.string = &local, .index = 0))
        if data&!= 65 {
            status_code = 2
            return
        }
        deinit(.self = $&local)
        i = i + 1
    }
}
