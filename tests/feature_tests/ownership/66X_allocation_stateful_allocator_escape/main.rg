LocalAllocator : Type = (.deallocations: Int32)

allocate(.self: $&LocalAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size)
    address :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&LocalAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = data.address
    free(.address = address)
}

LocalAllocator implements Allocator
LocalAllocator implements Deallocator

make() -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    allocator_storage :: LocalAllocator = (.deallocations = 0)
    assume allocator ::= $&allocator_storage
    result = allocate(.self = $&allocator_storage, .size = 1)
}

main() -> (.status_code: Int32) := {
    escaped ::= make()
    status_code = 0
}
