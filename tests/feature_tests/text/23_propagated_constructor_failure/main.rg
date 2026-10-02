FailingAllocator : Type = (.attempts: Int32)

allocate(.self: $&FailingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.attempts = self&.attempts + 1
    result = ..error(.reason = ..out_of_memory)
}

deallocate(.self: $&FailingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {}

FailingAllocator implements Allocator
FailingAllocator implements Deallocator

main() -> (.status_code: Int32 = 0) := {
    failing :: FailingAllocator = (.attempts = 0)
    string_result ::= String(.allocator = $&failing, .length = 1)
    match string_result {
        ..ok _ { status_code = 1 }
        ..error ~ err { if err.reason != ..out_of_memory { status_code = 4 } }
    }
    path_result ::= Path(.allocator = $&failing, .view = c_string_as_view(.text = "path"))
    match path_result {
        ..ok _ { status_code = 2 }
        ..error ~ err { if err.reason != ..out_of_memory { status_code = 5 } }
    }
    if failing.attempts != 2 { status_code = 3 }
}
