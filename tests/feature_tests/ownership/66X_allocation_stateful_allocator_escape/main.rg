LocalAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .deallocations: Int32
)

allocate(.self: $&LocalAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    address :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&LocalAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = data.address
    free(.address = address, .ffi = self&.ffi)
}

LocalAllocator implements Allocator
LocalAllocator implements Deallocator

make(.ffi: $&ForeignFunctionInterface
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    allocator_storage :: LocalAllocator = (.ffi = ffi, .deallocations = 0)
    assume allocator ::= $&allocator_storage
    result = allocate(.self = $&allocator_storage, .size = 1)
}

main(.system: System) -> (.status_code: Int32) := {
    escaped ::= make(.ffi = system.ffi)
    status_code = 0
}
