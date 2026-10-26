unsafe_allocation := import ("../../_support/unsafe_allocation")

Pair := (
    .changing : String
    .stable   : String
)

implement Deinit<Pair> (
    .deinit = (.self: $&Pair) -> () {
        deinit(.self = $&self&.changing)
        deinit(.self = $&self&.stable)
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    pair ::= Pair(
        .changing = unwrap_or_abort(
            .value = string_with_capacity(.allocator = $&allocator_storage, .capacity = 1)
        )
        .stable = unwrap_or_abort(
            .value = string_with_capacity(.allocator = $&allocator_storage, .capacity = 1)
        )
    )
    stable_push ::= push_ascii(
        .self = $&pair.stable, .byte = 42, .allocator = $&allocator_storage
    )
    if is(.value = stable_push, .variant = ..error) {
        return
    }
    stable_data ::= unwrap_or_abort(
        .value = string_byte_reference(.string = &pair.stable, .index = 0)
    )
    i :: UIntNative = 0
    while i < 2 {
        pushed ::= push_ascii(
            .self = $&pair.changing, .byte = 65, .allocator = $&allocator_storage
        )
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&pair.stable, .index = 0, .byte = 42))
    if byte_length(&pair.changing).count != 2 or stable_data&!= 42 {
        status_code = 2
        return
    }
    deinit(.self = $&pair)
}
