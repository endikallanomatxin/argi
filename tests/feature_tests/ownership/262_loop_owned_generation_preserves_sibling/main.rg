unsafe_allocation := import("../../_support/unsafe_allocation")
Pair : Type = (
    .changing: String
    .stable: String
)

Pair deinit(.self: $&Pair, .allocator: $&Allocator) -> () := {
    assume allocator

    deinit(.self = $&self&.changing, .allocator = allocator)
    deinit(.self = $&self&.stable, .allocator = allocator)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    pair ::= Pair(
        .changing = unwrap_or_abort(.value = String(.allocator = $&allocator_storage, .capacity = 1)),
        .stable = unwrap_or_abort(.value = String(.allocator = $&allocator_storage, .capacity = 1)),
    )
    stable_push ::= push_byte(.self = $&pair.stable, .byte = 42, .allocator = $&allocator_storage)
    if is(.value = stable_push, .variant = ..error) {
        return
    }
    stable_data ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&pair.stable.allocation, .offset = 0).reference
    i :: UIntNative = 0
    while i < 2 {
        pushed ::= push_byte(.self = $&pair.changing, .byte = 65, .allocator = $&allocator_storage)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    stable_data& = 42
    if pair.changing.length != 2 or stable_data& != 42 {
        status_code = 2
        return
    }
    deinit(.self = $&pair, .allocator = $&allocator_storage)
}
