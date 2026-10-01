unsafe_allocation := import("../../_support/unsafe_allocation")

Owned : Type = (.allocation: Allocation)

init(.p: $&Owned, .allocator: $&Allocator) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    allocated ::= allocate(.self = allocator, .size = 1)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            p& = (.allocation = ~payload)
            result = ..ok Void()
        }
    }
}

deinit(.self: $&Owned) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    result ::= Owned(.allocator = $&allocator_storage)
    match result {
        ..error _ {}
        ..ok ~ value {
            owner ::= ~value
            reference ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&owner.allocation, .offset = 0).reference
            deinit(.self = $&owner)
            if reference& != 0 { status_code = 1 }
        }
    }
}
