FailingAllocator : Type = (.attempts: UIntNative = 0)
allocate(.self: $&FailingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.attempts = self&.attempts + 1
    result = ..error(.reason = ..out_of_memory)
}
deallocate(.self: $&FailingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := { abort }
FailingAllocator implements Allocator
FailingAllocator implements Deallocator
main() -> (.status_code: Int32 = 0) := {
    allocator :: FailingAllocator = (.attempts = 0)
    match RingBuffer#(.t: Int32)(.capacity = 0, .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..invalid_capacity { abort } }
    }
    maximum :: UIntNative = 0
    index :: UIntNative = 0
    while index < size_of(.type = UIntNative) {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    match RingBuffer#(.t: Int32)(.capacity = maximum, .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..out_of_memory { abort } }
    }
    if allocator.attempts != 0 { abort }
    match RingBuffer#(.t: Int32)(.capacity = 2, .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..out_of_memory { abort } }
    }
    if allocator.attempts != 1 { abort }
}
