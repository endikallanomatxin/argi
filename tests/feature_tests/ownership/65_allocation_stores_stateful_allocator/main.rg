CountingAllocator : Type = (.deallocations: Int32)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.allocation: Allocation) := {
    storage ::= malloc(.size = size)
    address :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    data ::= cast#(.to: $&UInt8)(.value = address)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation = establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
}

deallocate(.self: $&CountingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.pointer = cast#(.to: &Any)(.value = address))
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (.deallocations = 0)
    allocation ::= allocate_owned(.self = $&allocator, .size = 1)
    allocation.data& = 7
    deinit(.self = $&allocation)

    if allocator.deallocations == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
}
