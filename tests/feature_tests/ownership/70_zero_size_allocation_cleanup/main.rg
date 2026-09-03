CountingAllocator : Type = (.deallocations: Int32)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = 1)
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&CountingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = cast#(.to: UIntNative)(.value = data))
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (.deallocations = 0)
    result ::= allocate(.self = $&allocator, .size = 0)
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
    status_code = allocator.deallocations - 1
}
