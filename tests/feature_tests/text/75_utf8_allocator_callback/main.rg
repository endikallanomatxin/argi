MutatingAllocator := (.source: $&[3]UInt8, .backing: $&PageAllocator)

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

main := (.system: System) -> () {

    bytes: [3]UInt8 = (65, 66, 0)
    page :: PageAllocator = PageAllocator(.memory = system.memory)
    allocator ::= MutatingAllocator(.source = $&bytes, .backing = $&page)
    allocator_virtual ::= to_virtual#(Allocator)($&allocator)
    match string_from_bytes(.bytes = view(&bytes), .allocator = $&allocator_virtual) {
        ..ok ~text { abort }
        ..error failure { if failure.reason != ..invalid_utf8 { abort } }
    }
    bytes[0] = 65
    text ::= unwrap_or_abort(
        .value = string_with_capacity(.capacity = 1, .allocator = system.page_allocator)
    )
    unwrap_or_abort(.value = push_ascii($&text, .byte = 88, .allocator = system.page_allocator))
    c_source ::= trusted_reinterpret_reference#(.from: UInt8, .to: CChar)(
        .base = &bytes[0]
    ).reference
    match push_c_string($&text, .text = c_source, .allocator = $&allocator_virtual) {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..invalid_utf8 { abort } }
    }
    if view(&text) != "X" { abort }

}
