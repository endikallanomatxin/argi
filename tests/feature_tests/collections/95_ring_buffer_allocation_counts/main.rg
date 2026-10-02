RecordingAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .allocations: UIntNative = 0
    .deallocations: UIntNative = 0
)
allocate(.self: $&RecordingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
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
    ring ::= unwrap_or_abort(.value = RingBuffer#(.t: Int32)(.capacity = 1, .allocator = $&allocator))
    index :: Int32 = 0
    while index < 20 {
        unwrap_or_abort(.value = push(.self = $&ring, .value = index, .allocator = $&allocator))
        match push(.self = $&ring, .value = 100, .allocator = $&allocator).result {
            ..ok _ { abort }
            ..error ~ err { if err.reason != ..full { abort } }
        }
        if unwrap_or_abort(.value = pop(.self = $&ring)) != index { abort }
        match pop(.self = $&ring).result {
            ..ok _ { abort }
            ..error ~ err { if err.reason != ..empty { abort } }
        }
        index = index + 1
    }
    if allocator.allocations != 1 or allocator.deallocations != 0 { abort }
    deinit(.self = $&ring, .allocator = $&allocator)
    if allocator.deallocations != 1 { abort }
    strings ::= unwrap_or_abort(.value = RingBuffer#(.t: String)(.capacity = 1, .allocator = $&allocator))
    first ::= unwrap_or_abort(.value = String(.allocator = $&allocator, .length = 1))
    rejected ::= unwrap_or_abort(.value = String(.allocator = $&allocator, .length = 1))
    bytes_set(.string = $&first, .index = 0, .value = 97)
    unwrap_or_abort(.value = push(.self = $&strings, .value = ~first, .allocator = $&allocator))
    if is(.value = push(.self = $&strings, .value = ~rejected, .allocator = $&allocator), .variant = ..error) == false { abort }
    if allocator.allocations != 4 or allocator.deallocations != 2 { abort }
    survivor ::= unwrap_or_abort(.value = pop(.self = $&strings))
    deinit(.self = $&strings, .allocator = $&allocator)
    if allocator.deallocations != 3 { abort }
    if as_view(.self = &survivor).view != "a" { abort }
    deinit(.self = $&survivor, .allocator = $&allocator)
    if allocator.deallocations != 4 { abort }
}
