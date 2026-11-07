ShortAllocator := (.backing: $&CAllocator)
implement Allocator#(ShortAllocator) (
    .allocate = (.self: $&ShortAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        physical_size :: UIntNative = 1
        allocation ::= allocate_bytes(.self = self&.backing, .size = physical_size, .alignment = alignment)!
        -- Public size cannot enlarge the private backing reservation.
        allocation.size = size
        result = ..ok ~allocation
    }
)
main := (.system: System) -> () {
    backing ::= CAllocator(.ffi = system.ffi)
    provider ::= ShortAllocator($&backing)
    allocation ::= unwrap_or_abort(.value = allocate_bytes(.self = $&provider, .size = 64, .alignment = 8))
}
