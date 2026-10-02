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
    parts : [2]StringView = ("a", "b")
    match join(.parts = array_view_ro(.array = &parts).view, .separator = ",", .allocator = $&allocator) {
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
    -- Deliberately inconsistent extents exercise length rejection before any
    -- byte access; these descriptors must never reach text-reading operations.
    byte :: UInt8 = 0
    huge :: StringView = (.data = &byte, .length = maximum)
    single : [1]StringView = (huge)
    match join(.parts = array_view_ro(.array = &single).view, .separator = "", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..size_overflow { abort } }
    }
    match join(.parts = array_view_ro(.array = &parts).view, .separator = huge, .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..size_overflow { abort } }
    }
    almost :: StringView = (.data = &byte, .length = maximum - 1)
    overflowing_sum : [2]StringView = (almost, "a")
    match join(.parts = array_view_ro(.array = &overflowing_sum).view, .separator = "", .allocator = $&allocator) {
        ..ok _ { abort }
        ..error ~ err { if err.reason != ..size_overflow { abort } }
    }
    if allocator.attempts != 1 { abort }
}
