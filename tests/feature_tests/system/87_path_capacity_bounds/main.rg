FailingAllocator: Type = (.attempts: UIntNative = 0)

allocate(
        .self      : $&FailingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative          = 1
    ) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) := {
    self&.attempts = self&.attempts + 1
    result = ..error(.reason = ..out_of_memory)
}

deallocate(
        .self      : $&FailingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () := { abort }

FailingAllocator implements Allocator
FailingAllocator implements Deallocator

main() -> (.status_code: Int32 = 0) := {
    native :: UIntNative = 0
    maximum ::= integer_limits(.value = native).maximum
    byte :: UInt8 = 97
    huge :: StringView = (.data = &byte, .length = maximum)
    small :: StringView = "a"
    empty :: StringView = ""
    failing ::= FailingAllocator()
    match join_views(.left = &huge, .right = &small, .allocator = $&failing) {
        ..ok _ { abort } ..error _ {}
    }
    match join_views(.left = &small, .right = &huge, .allocator = $&failing) {
        ..ok _ { abort } ..error _ {}
    }
    match join_views(.left = &huge, .right = &empty, .allocator = $&failing) {
        ..ok _ { abort } ..error _ {}
    }
    near :: StringView = (.data = &byte, .length = maximum - 2)
    match join_views(.left = &small, .right = &near, .allocator = $&failing) {
        ..ok _ { abort } ..error _ {}
    }
    if failing.attempts != 0 { abort }
}
