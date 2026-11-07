ShortAllocator := (.backing: $&CAllocator)
implement Allocator#(ShortAllocator) (
    .allocate = (.self: $&ShortAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        physical_size ::= size
        if physical_size < 4096 { physical_size = 4096 }
        allocation ::= allocate_bytes(.self = self&.backing, .size = physical_size, .alignment = alignment)!
        -- Public metadata must not hide an actually misaligned start address.
        allocation.data.address = allocation.data.address + 1
        allocation.size = physical_size - 1
        result = ..ok ~allocation
    }
)
main := (.system: System) -> () {
    backing ::= CAllocator(.ffi = system.ffi)
    provider ::= ShortAllocator($&backing)
    allocation ::= unwrap_or_abort(.value = allocate_bytes(.self = $&provider, .size = 64, .alignment = 8))
}
