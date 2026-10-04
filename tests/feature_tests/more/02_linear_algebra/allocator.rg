RefusingAllocator: Type = (.attempts: UIntNative)
RefusingAllocator implements Allocator
RefusingAllocator implements Deallocator
allocate(.self: $&RefusingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation,

        .reasons : (..out_of_memory))) := {
    self&.attempts = self&.attempts + 1
    result = ..error(.reason = ..out_of_memory)
}
deallocate(.self: $&RefusingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative,
    .alignment : UIntNative) -> () := {}
