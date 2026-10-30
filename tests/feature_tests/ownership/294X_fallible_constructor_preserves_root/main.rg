unsafe_allocation := import ("../../_support/unsafe_allocation")

Owned := (.allocation: Allocation)

OwnedInitArgs: Type = #(.AllocatorProvider: Type: Allocator) (
    .allocator : $&AllocatorProvider
)

implement#(.AllocatorProvider: Type: Allocator) Init#(Owned, OwnedInitArgs#(AllocatorProvider)) (
    .Result : Type = Errable#(.t: Owned, .reasons: (..out_of_memory))

    .init = OwnedInitArgs#(AllocatorProvider) -> (.result: Result) {

        _init_allocator ::= ~allocator

        constructed :: Owned

        allocated ::= allocate_bytes(.self = _init_allocator, .size = 1)
        match allocated {
            ..error _ { result = ..error(.reason = ..out_of_memory) }
            ..ok ~payload {
                constructed = (.allocation = ~payload)
                result = ..ok ~constructed
            }
        }
    }
)

implement Deinit#(Owned) (
    .deinit = (.self: $&Owned) -> () {
        deinit(.self = $&self&.allocation)
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    result ::= Owned(.allocator = $&allocator_storage)
    match result {
        ..error _ {}
        ..ok ~value {
            owner ::= ~value
            reference ::= unsafe_allocation.trusted_allocation_byte_rw(
                .allocation = $&owner.allocation, .offset = 0
            ).reference
            deinit(.self = $&owner)
            if reference&!= 0 { status_code = 1 }
        }
    }
}
