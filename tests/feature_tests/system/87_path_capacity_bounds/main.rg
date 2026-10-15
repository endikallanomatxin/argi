FailingAllocator: Type = (.attempts: UIntNative = 0)

main() -> (.status_code: Int32 = 0) := {
    left: StringView = "left"
    right: StringView = "right"
    failing ::= FailingAllocator()
    match join_views(.left = &left, .right = &right, .allocator = $&failing) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if failing.attempts != 1 { abort }

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
    ) -> () { abort }
)
