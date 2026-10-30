FailingAllocator := (.attempts: Int32)

main := () -> (.status_code: Int32 = 0) {

    failing :: FailingAllocator = (.attempts = 0)
    string_result ::= String(.allocator = $&failing, .length = 1)
    match string_result {
        ..ok _ { status_code = 1 }
        ..error ~err { if err.reason != ..out_of_memory { status_code = 4 } }
    }
    path_result ::= path_with_view(.allocator = $&failing, .view = "path")
    match path_result {
        ..ok _ { status_code = 2 }
        ..error ~err { if err.reason != ..out_of_memory { status_code = 5 } }
    }
    if failing.attempts != 2 { status_code = 3 }
}

implement Allocator#(FailingAllocator) (
    .allocate = (.self: $&FailingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {

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
