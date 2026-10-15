MutatingAllocator: Type = (.source: $&[3]UInt8, .backing: $&PageAllocator)

implement Allocator#(MutatingAllocator) (
    .allocate = (.self: $&MutatingAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) {
        self&.source&[0] = 255
        result = Allocator#(
            PageAllocator
        ).allocate(self&.backing, .size = size, .alignment = alignment)
    }
)

main(.system: System) -> () := {
    bytes: [3]UInt8 = (65, 66, 0)
    allocator ::= MutatingAllocator(.source = $&bytes, .backing = system.page_allocator)
    match string_from_bytes(.bytes = view(&bytes), .allocator = $&allocator) {
        ..ok ~text { abort }
        ..error failure { if failure.reason != ..invalid_utf8 { abort } }
    }
    bytes[0] = 65
    text ::= unwrap_or_abort(
        .value = string_with_capacity(.capacity = 1, .allocator = system.page_allocator)
    )
    unwrap_or_abort(.value = push_ascii($&text, .byte = 88, .allocator = system.page_allocator))
    c_source ::= trusted_reinterpret_reference#(.from: UInt8, .to: Char)(
        .base = &bytes[0]
    ).reference
    match push_c_string($&text, .text = c_source, .allocator = $&allocator) {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..invalid_utf8 { abort } }
    }
    if as_view(&text) != "X" { abort }

}
