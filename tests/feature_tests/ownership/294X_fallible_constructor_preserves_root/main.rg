unsafe_allocation := import("../../_support/unsafe_allocation")

Owned : Type = (.allocation: Allocation)

implement#(.AllocatorProvider: Type: Allocator) Init#(Owned, (.allocator: $&AllocatorProvider)) (
    .Result: Type = Errable#(.t: Owned, .reasons: (..out_of_memory))
    .init = (.args: (.allocator: $&AllocatorProvider)) -> (.result: Result) {
        allocator ::= ~args.allocator

        constructed :: Owned

        allocated ::= allocate_bytes(.self = allocator, .size = 1)
        match allocated {
            ..error _ { result = ..error(.reason = ..out_of_memory) }
            ..ok ~ payload {
                constructed = (.allocation = ~payload)
                result = ..ok ~constructed
            }
        }
    }
)

Owned deinit(.self: $&Owned) -> () := {
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
