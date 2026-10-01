RecordingAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .fail: Bool = false
    .allocations: UIntNative = 0
    .deallocations: UIntNative = 0
)
allocate(.self: $&RecordingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    if self&.fail {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    self&.allocations = self&.allocations + 1
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    if UIntNative(.value = storage) == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= trusted_establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}
deallocate(.self: $&RecordingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = data.address, .ffi = self&.ffi)
}
RecordingAllocator implements Allocator
RecordingAllocator implements Deallocator
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: RecordingAllocator = (.ffi = system.ffi)
    set ::= unwrap_or_abort(.value = HashSet#(.key: UIntNative, .policy: UIntNativeHashPolicy)(.policy = UIntNativeHashPolicy(), .allocator = $&allocator))
    missing :: UIntNative = 4
    zero :: UIntNative = 0
    index :: UIntNative = 0
    while index < 4 {
        unwrap_or_abort(.value = insert(.self = $&set, .key = index, .allocator = $&allocator))
        index = index + 1
    }
    allocator.fail = true
    if unwrap_or_abort(.value = insert(.self = $&set, .key = zero, .allocator = $&allocator)) { abort }
    match insert(.self = $&set, .key = missing, .allocator = $&allocator).result {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..out_of_memory { abort } }
    }
    if length(.self = &set).count != 4 or contains(.self = &set, .key = missing).ok { abort }
    if contains(.self = &set, .key = zero).ok == false { abort }
    allocator.fail = false
    unwrap_or_abort(.value = insert(.self = $&set, .key = missing, .allocator = $&allocator))
    deinit(.self = $&set, .allocator = $&allocator)
    if allocator.allocations != 2 or allocator.deallocations != 2 { abort }
}
