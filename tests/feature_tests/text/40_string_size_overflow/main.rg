FailingAllocator: Type = (.attempts: UIntNative = 0)

main(.system: System) -> (.status_code: Int32 = 0) := {
    maximum :: UIntNative = 0
    index :: UIntNative = 0
    while index < size_of(.type = UIntNative) {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    failing :: FailingAllocator = (.attempts = 0)
    if is(
        .value = string_with_length(.allocator = $&failing, .length = maximum), .variant = ..ok
    ) {
        abort
    }
    if is(
        .value   = string_with_capacity(.allocator = $&failing, .capacity = maximum)
        .variant = ..ok
    ) { abort }
    if is(.value = String(.allocator = $&failing, .length = maximum), .variant = ..ok) {
        abort
    }
    if is(
        .value   = string_with_capacity(.allocator = $&failing, .capacity = maximum)
        .variant = ..ok
    ) { abort }
    if failing.attempts != 0 { abort }
    -- The largest representable capacity still reaches the allocator. The
    -- failing allocator prevents enormous allocation and initialization.
    if is(
        .value   = string_with_length(.allocator = $&failing, .length = maximum - 1)
        .variant = ..ok
    ) { abort }
    if failing.attempts != 1 { abort }
    text ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 97))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 98))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 99))
    if is(
        .value   = ensure_capacity(.self = $&text, .capacity = maximum, .allocator = $&failing)
        .variant = ..ok
    ) { abort }
    if failing.attempts != 1 { abort }
    if as_view(.self = &text).view != "abc" { abort }
    -- Ordinary growth failures preserve the original text too.
    if is(
        .value   = push_ascii(.self = $&text, .byte = 100, .allocator = $&failing)
        .variant = ..ok
    ) {
        abort
    }
    if failing.attempts != 2 { abort }
    if as_view(.self = &text).view != "abc" { abort }
    if bytes_get(.view = &text, .index = 3).byte != 0 { abort }
    clear(.self = $&text)
    append_ascii_assume_capacity(.self = $&text, .byte = 120)
    tail: [2]UInt8 = (121, 122)
    append_text_assume_capacity(.self = $&text, .text = "yz")
    empty: [0]UInt8 = ()
    append_text_assume_capacity(.self = $&text, .text = "")
    if as_view(.self = &text).view != "xyz" { abort }
    if bytes_get(.view = &text, .index = 3).byte != 0 { abort }
    deinit(.self = $&text)
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
