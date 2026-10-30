CountingTracer := (.captures: UIntNative = 0)

implement ErrorTracer#(CountingTracer) (
    .add_context = (
        .self: $&CountingTracer, .location: SourceLocationId, .context: StringView
    ) -> () {
        self&.captures = self&.captures + 1
    }
    .reset_context = (.self: $&CountingTracer) -> () { self&.captures = 0 }
    .report        = (.self: $&CountingTracer, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {

        result = ..ok Void()
    }
)

RecordingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .fail          : Bool                       = false
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
)

Tracked := (.id: Int32)

drops :: Int32 = 0

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        drops = drops + 1
    }
)

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    tracer ::= CountingTracer()
    trace_handle ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&trace_handle
    allocator :: RecordingAllocator = (.ffi = system.ffi)
    queue ::= Deque#(.t: Tracked)(.capacity = 2, .allocator = $&allocator)!!!
    push_back(.self = $&queue, .value = Tracked(.id = 1), .allocator = $&allocator)!!!
    push_back(.self = $&queue, .value = Tracked(.id = 2), .allocator = $&allocator)!!!
    first ::= pop_front(.self = $&queue)!!!
    push_back(.self = $&queue, .value = Tracked(.id = 3), .allocator = $&allocator)!!!
    allocator.fail = true
    captures_before ::= tracer.captures
    match reserve(.self = $&queue, .capacity = 3, .allocator = $&allocator) {
        ..ok _ { abort } ..error _ {}
    }
    reserve_captures ::= tracer.captures - captures_before
    captures_before = tracer.captures
    match push_front(.self = $&queue, .value = Tracked(.id = 4), .allocator = $&allocator) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if tracer.captures != captures_before + reserve_captures { abort }
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
    reserve(.self = $&queue, .capacity = 8, .allocator = $&allocator)!!!
    if allocator.allocations != 2 or allocator.deallocations != 1 or drops != 1 { abort }
    front ::= pop_front(.self = $&queue)!!!
    back ::= pop_back(.self = $&queue)!!!
    if front.id != 2 or back.id != 3 { abort }
    deinit(.self = $&queue)
    if allocator.deallocations != 2 or drops != 1 { abort }
    deinit(.self = $&first)
    deinit(.self = $&front)
    deinit(.self = $&back)
    if drops != 4 { abort }
    status_code = 0
}

implement Allocator#(RecordingAllocator) (
    .allocate = (.self: $&RecordingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {

        if self&.fail {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        self&.allocations = self&.allocations + 1
        storage ::= malloc(.size = size, .ffi = self&.ffi)
        if storage | convert#(.to: UIntNative)(_) == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        deallocator :: Virtual#(Deallocator) = to_virtual#(.contract: Deallocator)(
            .value = self
        )
        allocation ::= trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
        result = ..ok ~allocation
    }
)

implement Deallocator#(RecordingAllocator) (
    .deallocate = (
        .self      : $&RecordingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        self&.deallocations = self&.deallocations + 1
        free(.address = data.address, .ffi = self&.ffi)
    }
)
