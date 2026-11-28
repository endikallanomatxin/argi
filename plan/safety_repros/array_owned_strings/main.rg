main := (.system: System) -> () {
    provider ::= GeneralPurposeAllocator(system.page_allocator)
    assume allocator ::= Virtual#(Allocator)($&provider)
    array ::= unwrap_or_abort(DynamicArray#(String)(.capacity = 1))
    index :: UIntNative = 0
    while index < 100 {
        text ::= unwrap_or_abort(String(.length = 1))
        unwrap_or_abort(set_ascii($&text, .index = 0, .byte = 65))
        unwrap_or_abort(push($&array, .value = ~text))
        index = index + 1
    }
    first ::= unwrap_or_abort(get_reference(&array, .index = 0))
    if unwrap_or_abort(bytes_get(.view = first, .index = 0)) != 65 { abort }
    deinit($&array)
    if has_live_allocations(&provider).has_live { abort }
}
