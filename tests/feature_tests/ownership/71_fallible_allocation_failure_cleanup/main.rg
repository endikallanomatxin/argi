FailingAllocator : Type = (
    .allocations: Int32
    .deallocations: Int32
)

allocate(.self: $&FailingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.allocations = self&.allocations + 1
    result = ..error(.reason = ..out_of_memory)
}

deallocate(.self: $&FailingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
}

FailingAllocator implements Allocator
FailingAllocator implements Deallocator

main() -> (.status_code: Int32) := {
    allocator_storage :: FailingAllocator = (
        .allocations = 0,
        .deallocations = 0,
    )
    assume allocator ::= $&allocator_storage
    result ::= allocate(.self = $&allocator_storage, .size = 8)
    if is(.value = result, .variant = ..error) {
        status_code = allocator_storage.allocations * 10 + allocator_storage.deallocations - 10
        return
    }
    status_code = 1
}
