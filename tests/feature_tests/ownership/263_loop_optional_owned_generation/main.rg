Holder := (
    .buffer : String
)

HolderInitArgs: Type = (
    .allocator : Virtual#(Allocator)
)

implement Init#(
    Holder, HolderInitArgs
) (
    .Result : Type = Holder

    .init = HolderInitArgs -> (.result: Result) {

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

append := (
    .self: $&Holder, .allocator: Virtual#(Allocator)
) -> () {

    assume allocator

    _ ::= push_ascii(.self = $&self&.buffer, .byte = 65, .allocator = allocator)
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    holder ::= Holder(.allocator = allocator)
    i :: UIntNative = 0
    while i < 1 {
        append(.self = $&holder, .allocator = allocator)
        i = i + 1
    }

    if byte_length(&holder.buffer).count != 1 {
        status_code = 1
        return
    }
    deinit(.self = $&holder)
}
