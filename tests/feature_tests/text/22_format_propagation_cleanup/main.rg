FailSecondAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .allocations: Int32
    .deallocations: Int32
)

FailSecondAllocator init(.ffi: $&ForeignFunctionInterface) -> (.result: FailSecondAllocator) := {
    result = (.ffi = ffi, .allocations = 0, .deallocations = 0)
}

allocate(.self: $&FailSecondAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.allocations = self&.allocations + 1
    if self&.allocations > 1 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= trusted_establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&FailSecondAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = data.address, .ffi = self&.ffi)
}

FailSecondAllocator implements Allocator
FailSecondAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32 = 0) := {
    backing ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    out ::= unwrap_or_abort(.value = String(.allocator = $&backing, .capacity = 1))
    failing ::= FailSecondAllocator(.ffi = system.ffi)
    formatted ::= format_into(.out = $&out, .value = -105, .allocator = $&failing)
    if is(.value = formatted, .variant = ..ok) { status_code = 1 }
    if failing.allocations != 2 or failing.deallocations != 1 { status_code = 2 }
    deinit(.self = $&out, .allocator = $&backing)
}
