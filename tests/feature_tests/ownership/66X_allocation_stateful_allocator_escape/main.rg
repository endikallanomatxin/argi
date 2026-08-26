LocalAllocator : Type = (.deallocations: Int32)

allocate(.self: $&LocalAllocator, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size)
    address :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&LocalAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.address = address)
}

LocalAllocator implements Allocator
LocalAllocator implements Deallocator

make() -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    allocator :: LocalAllocator = (.deallocations = 0)
    result = allocate(.self = $&allocator, .size = 1)
}

main() -> (.status_code: Int32) := {
    escaped ::= make()
    status_code = 0
}
