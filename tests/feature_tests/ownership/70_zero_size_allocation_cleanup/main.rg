CountingAllocator : Type = (.deallocations: Int32)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.allocation: Allocation) := {
    storage ::= malloc(.size = size)
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = self)
    allocation = establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
}

deallocate(.self: $&CountingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = data)))
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (.deallocations = 0)
    allocation ::= allocate(.self = $&allocator, .size = 0)
    deinit(.self = $&allocation)
    status_code = allocator.deallocations - 1
}
