FailingAllocator := (.attempts: UIntNative = 0)

main := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.status_code: Int32 = 0) {
    assume error_tracer
    allocator :: FailingAllocator = (.attempts = 0)
    parts: [2]StringView = ("a", "b")
    match join(.parts = view(.self = &parts), .separator = ",", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~err { if err.reason != ..out_of_memory { abort } }
    }
    if allocator.attempts != 1 { abort }

}

implement Allocator#(FailingAllocator) (
    .allocate = (
        .self         : $&FailingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative              = 1,
        .error_tracer : $&Virtual#(ErrorTracer)
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
