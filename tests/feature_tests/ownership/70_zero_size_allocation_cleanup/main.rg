CountingAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .deallocations: Int32)

allocate(.self: $&CountingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = 1, .ffi = self&.ffi)
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&CountingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = data.address, .ffi = self&.ffi)
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: CountingAllocator = (.deallocations = 0)
    assume allocator ::= $&allocator_storage
    result ::= allocate(.self = $&allocator_storage, .size = 0)
    match result {
        ..ok ~ payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
        }
        ..error _ {
            status_code = 2
            return
        }
    }
    status_code = allocator_storage.deallocations - 1
}
