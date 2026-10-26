main := (.system: System) -> ()  {
    assume allocator := system.page_allocator
    j :: UIntNative = 0
    while j < 2 {
        field ::= unwrap_or_abort(.value = DynamicArray<UInt8>(.capacity = 16))
        i :: UIntNative = 0
        while i < 3 {
            if i == 1 {
                unwrap_or_abort(.value = push(.self = $&field, .value = 65))
                i = i + 1
                continue
            }
            unwrap_or_abort(.value = push(.self = $&field, .value = 65))
            i = i + 1
        }
        text ::= unwrap_or_abort(.value = string_from_bytes(.bytes = view(&field)))
        if view(&text) != "AAA" { abort }
        j = j + 1
    }
}
