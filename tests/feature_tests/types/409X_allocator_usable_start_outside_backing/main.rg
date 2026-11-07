ShortAllocator := (.backing: $&CAllocator)
implement Allocator#(ShortAllocator) (
    .allocate = (.self: $&ShortAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        physical_size ::= size
        if physical_size < 4096 { physical_size = 4096 }
        allocation ::= allocate_bytes(.self = self&.backing, .size = physical_size, .alignment = alignment)!
        -- Even an aligned public start cannot move the authenticated extent.
        allocation.data.address = allocation.data.address + physical_size
        allocation.size = size
        result = ..ok ~allocation
    }
)
main := (.system: System) -> () {
    backing ::= CAllocator(.ffi = system.ffi)
    provider ::= ShortAllocator($&backing)
    allocation ::= unwrap_or_abort(.value = allocate_bytes(.self = $&provider, .size = 64, .alignment = 8))
}
