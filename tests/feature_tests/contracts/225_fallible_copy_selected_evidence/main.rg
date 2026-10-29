drops :: Int32 = 0

record_drop := () -> () { drops = drops + 1 }

Owner := (.value: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () { record_drop() })

implement#(.Provider: Type: Allocator) FalliblyCopyable#(Owner, Provider) (
    .reasons : Type = (..copy_failed)
    .copy    = (.self: &Owner, .allocator: $&Provider, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(Owner, reasons)
    ) {
        assume error_tracer

        if self&.value == 13 {
            result = ..error(.reason = ..copy_failed)
            return
        }
        result = ..ok(.value = self&.value)
    }
)

check_failure := (.allocator: $&PageAllocator, .error_tracer: $&Virtual#(ErrorTracer)) -> () {
    assume error_tracer
    assume allocator
    source ::= unwrap_or_abort(DynamicArray#(Owner)(.capacity = 2))
    first ::= Owner(1)
    second ::= Owner(13)
    push_assume_capacity#(Owner)($&source, .value = ~first)
    push_assume_capacity#(Owner)($&source, .value = ~second)
    copied ::= FalliblyCopyable#(
        DynamicArray#(Owner), PageAllocator
    ).copy(&source, .allocator = allocator)
    match copied {
        ..ok ~value { abort }
        ..error error {
            if is(.value = error.reason, .variant = ..copy_failed) {} else { abort }
        }
    }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    value :: Int32 = 42
    copied ::= unwrap_or_abort(
        FalliblyCopyable#(Int32, PageAllocator).copy(&value, .allocator = allocator)
    )
    if copied != 42 { abort }
    source ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 1))
    push_assume_capacity#(Int32)($&source, .value = 42)
    output ::= unwrap_or_abort(
        FalliblyCopyable#(
            DynamicArray#(Int32), PageAllocator
        ).copy(&source, .allocator = allocator)
    )
    read ::= unwrap_or_abort(get_reference(&output, .index = 0))
    if read&!= 42 { abort }
    nested ::= unwrap_or_abort(DynamicArray#(DynamicArray#(Int32))(.capacity = 1))
    push_assume_capacity#(DynamicArray#(Int32))($&nested, .value = ~source)
    copied_nested ::= unwrap_or_abort(
        FalliblyCopyable#(
            DynamicArray#(DynamicArray#(Int32)), PageAllocator
        ).copy(&nested, .allocator = allocator)
    )
    inner ::= unwrap_or_abort(get_reference(&copied_nested, .index = 0))
    item ::= unwrap_or_abort(get_reference(inner, .index = 0))
    if item&!= 42 { abort }
    check_failure(allocator)
    if drops != 3 { abort }
}
