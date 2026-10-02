FailingAllocator : Type = (.attempts: UIntNative = 0)
allocate(.self: $&FailingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.attempts = self&.attempts + 1
    result = ..error(.reason = ..out_of_memory)
}
deallocate(.self: $&FailingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {}
FailingAllocator implements Allocator
FailingAllocator implements Deallocator
main() -> (.status_code: Int32 = 0) := {
    allocator :: FailingAllocator = (.attempts = 0)
    match replace(.self = "abc", .pattern = "", .replacement = "x", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..empty_pattern { abort } }
    }
    if allocator.attempts != 0 { abort }
    match replace(.self = "abc", .pattern = "b", .replacement = "x", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..out_of_memory { abort } }
    }
    if allocator.attempts != 1 { abort }
    maximum :: UIntNative = 0
    index :: UIntNative = 0
    while index < size_of(.type = UIntNative) {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    -- Inconsistent extents are only for rejection tests: no byte access is
    -- permitted to the fabricated replacement or unmatched source.
    byte :: UInt8 = 0
    huge :: StringView = (.data = &byte, .length = maximum)
    match replace(.self = "a", .pattern = "a", .replacement = huge, .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..size_overflow { abort } }
    }
    almost :: StringView = (.data = &byte, .length = maximum - 1)
    match replace(.self = "aa", .pattern = "a", .replacement = almost, .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..size_overflow { abort } }
    }
    match replace(.self = almost, .pattern = huge, .replacement = "", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..out_of_memory { abort } }
    }
    if allocator.attempts != 2 { abort }
}
