transfer_if := (
    .source: $&DynamicArray#(Int32), .destination: $&DynamicArray#(Int32), .move: Bool
) -> (.result: ?Int32) {
    if move {
        relocate(source, destination)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_concrete := $&GeneralPurposeAllocator(system.page_allocator)

    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)

    assume allocator := $&virtual_allocator

    source ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 2))
    unwrap_or_abort(push(.self = $&source, .value = 42, .allocator = allocator))
    destination ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 1))
    deinit(.self = $&destination)
    result ::= transfer_if($&source, $&destination, true)

    match result {
        ..some _ {
            offset :: UIntNative = 0
            element ::= unwrap_or_abort(get_reference(.self = &destination, .index = offset))
            if element&!= 42 { status_code = 1 }
        }
        ..none {
            offset :: UIntNative = 0
            element ::= unwrap_or_abort(get_reference(.self = &source, .index = offset))
            if element&!= 42 { status_code = 2 }
        }
    }

    if true {
        next_source ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 2))
        unwrap_or_abort(push(.self = $&next_source, .value = 43, .allocator = allocator))
        next_destination ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 1))
        deinit(.self = $&next_destination)
        transfer_if($&next_source, $&next_destination, true)
    }

    if true {
        next_source ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 2))
        unwrap_or_abort(push(.self = $&next_source, .value = 44, .allocator = allocator))
        next_destination ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 1))
        deinit(.self = $&next_destination)
        transfer_if($&next_source, $&next_destination, false)
    }
}
