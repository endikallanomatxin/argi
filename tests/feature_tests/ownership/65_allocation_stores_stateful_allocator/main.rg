CountingAllocator : Type = (.deallocations: Int32)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size)
    address :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&CountingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.address = address)
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (.deallocations = 0)
    result ::= allocate(.self = $&allocator, .size = 1)
    match result {
        ..ok ~ payload {
            allocation ::= ~payload
            allocation.data& = 7
            deinit(.self = $&allocation)
        }
        ..error _ {
            status_code = 2
            return
        }
    }

    if allocator.deallocations == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
}
