main := (.system: System) -> () {
    assume allocator := system.page_allocator
    array ::= unwrap_or_abort(DynamicArray#(UIntNative)(.capacity = 1))
    unwrap_or_abort(push($&array, .value = 42))
    saved ::= unwrap_or_abort(get_reference(&array, .index = 0))
    unwrap_or_abort(ensure_capacity(.self = $&array, .capacity = 100, .allocator = allocator))
    if saved& != 42 { abort }
}
