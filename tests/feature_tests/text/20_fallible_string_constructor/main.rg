main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator
    constructed ::= String(.allocator = allocator, .length = 3)
    match constructed {
        ..error _ { status_code = 1 }
        ..ok ~value {
            string ::= ~value
            if byte_length(&string).count != 3 { status_code = 2 }
            deinit(.self = $&string)
        }
    }
}
