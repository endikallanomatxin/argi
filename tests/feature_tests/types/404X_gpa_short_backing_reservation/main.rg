ShortAllocator := (.backing: $&CAllocator)
implement Allocator#(ShortAllocator) (
    .allocate = (.self: $&ShortAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        physical_size ::= size
        if physical_size < 4096 { physical_size = 4096 }
        allocation ::= allocate_bytes(.self = self&.backing, .size = physical_size, .alignment = alignment)!
        -- The backing is deliberately large so the old unchecked path would
        -- complete safely; the published usable reservation is only one byte.
        allocation.size = 1
        result = ..ok ~allocation
    }
)
main := (.system: System) -> () {
    backing ::= CAllocator(.ffi = system.ffi)
    provider ::= ShortAllocator($&backing)
    allocator ::= to_virtual#(Allocator)($&provider)
    gpa ::= GeneralPurposeAllocator(.allocator = allocator)
    allocation ::= unwrap_or_abort(.value = allocate_bytes(.self = $&gpa, .size = 8, .alignment = 8))
}
