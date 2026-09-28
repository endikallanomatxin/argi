unsafe_allocation := #import("../../_support/unsafe_allocation")
Stateful : Type = (
    .reference: $&UInt8
    .counter: Int32
)

mutate_conditionally(.self: $&Stateful, .condition: Bool) -> () := {
    if condition {
        self& = (
            .reference = self&.reference,
            .counter = self&.counter + 1,
        )
    }
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            state ::= Stateful(.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference, .counter = 0)
            mutate_conditionally(.self = $&state, .condition = true)
            deinit(.self = $&target)
            if state.reference& == 0 {
                status_code = 0
            }
        }
    }
}
