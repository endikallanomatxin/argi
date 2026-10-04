RecordingAllocator: Type = (
    .ffi           : $&ForeignFunctionInterface
    .fail          : Bool                       = false
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
)

allocate(
        .self      : $&RecordingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative            = 1
    ) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) := {
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
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(
        .value = self
    )
    allocation ::= trusted_establish_allocation(
        .storage     = storage
        .size        = size
        .alignment   = alignment
        .deallocator = deallocator
    )
    result = ..ok ~allocation
}

deallocate(
        .self      : $&RecordingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = data.address, .ffi = self&.ffi)
}

RecordingAllocator implements Allocator
RecordingAllocator implements Deallocator

Tracked: Type = (.id: Int32)

drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

main(.system: System) -> !Void = ..ok Void() := {
    allocator :: RecordingAllocator = (.ffi = system.ffi)
    queue ::= Deque#(.t: Tracked)(.capacity = 2, .allocator = $&allocator)!
    push_back(.self = $&queue, .value = Tracked(.id = 1), .allocator = $&allocator)!
    push_back(.self = $&queue, .value = Tracked(.id = 2), .allocator = $&allocator)!
    first ::= pop_front(.self = $&queue)!
    push_back(.self = $&queue, .value = Tracked(.id = 3), .allocator = $&allocator)!
    allocator.fail = true
    match push_front(.self = $&queue, .value = Tracked(.id = 4), .allocator = $&allocator) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if drops != 1 or length(.self = &queue).count != 2 or capacity(.self = &queue).count != 2 {
        abort
    }
    maximum :: UIntNative = 0
    index :: UIntNative = 0
    while index < size_of(.type = UIntNative) {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    match reserve(.self = $&queue, .capacity = maximum, .allocator = $&allocator) {
        ..ok _ { abort } ..error _ {}
    }
    if allocator.allocations != 1 or allocator.deallocations != 0 { abort }
    allocator.fail = false
    reserve(.self = $&queue, .capacity = 8, .allocator = $&allocator)!
    if allocator.allocations != 2 or allocator.deallocations != 1 or drops != 1 { abort }
    front ::= pop_front(.self = $&queue)!
    back ::= pop_back(.self = $&queue)!
    if front.id != 2 or back.id != 3 { abort }
    deinit(.self = $&queue, .allocator = $&allocator)
    if allocator.deallocations != 2 or drops != 1 { abort }
    deinit(.self = $&first)
    deinit(.self = $&front)
    deinit(.self = $&back)
    if drops != 4 { abort }
}
