FailingAllocator := (.attempts: UIntNative = 0)

main := () -> (.status_code: Int32 = 0) {
    allocator :: FailingAllocator = (.attempts = 0)
    match replace(.self = "abc", .pattern = "", .replacement = "x", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~err { if err.reason != ..empty_pattern { abort } }
    }
    if allocator.attempts != 0 { abort }
    match replace(.self = "abc", .pattern = "b", .replacement = "x", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~err { if err.reason != ..out_of_memory { abort } }
    }
    if allocator.attempts != 1 { abort }

}

implement Allocator#(FailingAllocator) (
    .allocate = (
        .self         : $&FailingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative                         = 1,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) {
        assume error_tracer

        self&.attempts = self&.attempts + 1
        result = ..error(.reason = ..out_of_memory)
    }
)

implement Deallocator#(FailingAllocator) (
    .deallocate = (
        .self      : $&FailingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {}
)
