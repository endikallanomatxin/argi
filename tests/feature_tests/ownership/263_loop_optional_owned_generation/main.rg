Holder := (
    .buffer : String
)

implement Init#(Holder) (
    .init = #(.AllocatorProvider: Type: Allocator) (.allocator: $&AllocatorProvider) -> (
        .result : Holder
    ) {
        _init_allocator ::= ~allocator

        assume allocator := _init_allocator

        result.buffer = unwrap_or_abort(
            .value = string_with_capacity(.allocator = _init_allocator, .capacity = 1)
        )
    }
)

implement Deinit#(Holder) (
    .deinit = (.self: $&Holder) -> () {
        deinit(.self = $&self&.buffer)
    }
)

append := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .self: $&Holder, .allocator: $&AllocatorType
) -> () {
    assume allocator

    _ ::= push_ascii(.self = $&self&.buffer, .byte = 65, .allocator = allocator)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    holder ::= Holder(.allocator = $&allocator_storage)
    i :: UIntNative = 0
    while i < 1 {
        append(.self = $&holder, .allocator = $&allocator_storage)
        i = i + 1
    }

    if byte_length(&holder.buffer).count != 1 {
        status_code = 1
        return
    }
    deinit(.self = $&holder)
}
