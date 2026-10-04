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

main(.system: System) -> (.status_code: Int32 = 0) := {
    maximum :: UIntNative = 0
    index :: UIntNative = 0
    while index < size_of(.type = UIntNative) {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    failing :: FailingAllocator = (.attempts = 0)
    if is(.value = string_with_length(.allocator = $&failing, .length = maximum), .variant = ..ok) {
        abort
    }
    if is(
        .value   = string_with_capacity(.allocator = $&failing, .capacity = maximum)
        .variant = ..ok
    ) { abort }
    if is(.value = String(.allocator = $&failing, .length = maximum), .variant = ..ok) { abort }
    if is(.value = String(.allocator = $&failing, .capacity = maximum), .variant = ..ok) { abort }
    if failing.attempts != 0 { abort }
    -- The largest representable capacity still reaches the allocator. The
    -- failing allocator prevents enormous allocation and initialization.
    if is(
        .value   = string_with_length(.allocator = $&failing, .length = maximum - 1)
        .variant = ..ok
    ) { abort }
    if failing.attempts != 1 { abort }
    text ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    bytes_set(.string = $&text, .index = 0, .value = 97)
    bytes_set(.string = $&text, .index = 1, .value = 98)
    bytes_set(.string = $&text, .index = 2, .value = 99)
    if is(
        .value   = ensure_capacity(.self = $&text, .capacity = maximum, .allocator = $&failing)
        .variant = ..ok
    ) { abort }
    byte :: UInt8 = 0
    -- Artificial lengths are only used by rejection paths, never byte reads.
    huge :: StringView = (.data = &byte, .length = maximum)
    if is(
        .value   = push_view(.self = $&text, .view = huge, .allocator = $&failing)
        .variant = ..ok
    ) { abort }
    nearly_huge :: StringView = (.data = &byte, .length = maximum - 3)
    if is(
        .value   = push_view(.self = $&text, .view = nearly_huge, .allocator = $&failing)
        .variant = ..ok
    ) { abort }
    small :: StringView = "a"
    if is(
        .value   = concat_views(.left = &huge, .right = &small, .allocator = $&failing)
        .variant = ..ok
    ) { abort }
    if is(
        .value   = concat_views(.left = &small, .right = &huge, .allocator = $&failing)
        .variant = ..ok
    ) { abort }
    if failing.attempts != 1 { abort }
    if as_view(.self = &text).view != "abc" { abort }
    original_size ::= text.allocation.size
    -- Corrupt only metadata to probe arithmetic edges, then restore it before
    -- touching the backing storage or cleaning it up.
    text.length = maximum
    if is(.value = copy(.self = &text, .allocator = $&failing), .variant = ..ok) { abort }
    text.length = maximum - 1
    if is(.value = push_byte(.self = $&text, .byte = 97, .allocator = $&failing), .variant = ..ok) {
        abort
    }
    text.length = 3
    text.allocation.size = maximum - 3
    if string_growth_capacity(.self = &text, .min_capacity = maximum - 5).value != maximum - 1 {
        abort
    }
    text.allocation.size = original_size
    if failing.attempts != 1 { abort }
    -- Ordinary growth failures preserve the original text too.
    if is(.value = push_byte(.self = $&text, .byte = 100, .allocator = $&failing), .variant = ..ok) {
        abort
    }
    if failing.attempts != 2 { abort }
    if as_view(.self = &text).view != "abc" { abort }
    if bytes_get(.string = &text, .index = 3).byte != 0 { abort }
    clear(.self = $&text)
    string_append_byte(.self = $&text, .byte = 120)
    tail: [2]UInt8 = (121, 122)
    string_append_bytes(.self = $&text, .source = array_view_ro(.array = &tail).view)
    empty: [0]UInt8 = ()
    string_append_bytes(.self = $&text, .source = array_view_ro(.array = &empty).view)
    if as_view(.self = &text).view != "xyz" { abort }
    if bytes_get(.string = &text, .index = 3).byte != 0 { abort }
    deinit(.self = $&text, .allocator = system.page_allocator)
}
