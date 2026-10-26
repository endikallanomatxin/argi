transfer_if := (
    .source: $&DynamicArray<Int32>, .destination: $&DynamicArray<Int32>, .move: Bool
) -> (.result: ?Int32) {
    if move {
        relocate(source, destination)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    escaped :: &Int32

    {
        source ::= unwrap_or_abort(DynamicArray<Int32>(.capacity = 2))
        unwrap_or_abort(push(.self = $&source, .value = 42))
        destination ::= unwrap_or_abort(DynamicArray<Int32>(.capacity = 1))
        deinit(.self = $&destination)
        offset :: UIntNative = 0
        escaped = unwrap_or_abort(get_reference(.self = &source, .index = offset))
        transfer_if($&source, $&destination, true)
    }

    status_code = escaped&
}
