unsafe_allocation := #import("../../_support/unsafe_allocation")
Buffer : Type = (
    .allocation: Allocation
)

release(.self: $&Buffer, .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    allocation ::= ~payload
    buffer :: Buffer = (.allocation = ~allocation)
    alias ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&buffer.allocation, .offset = 0).reference

    release(.self = $&buffer, .allocator = $&allocator_storage)
    if alias& == 0 {
        status_code = 0
    }
    }
    }
}
