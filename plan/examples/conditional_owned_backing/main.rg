main := (.system: System) -> () {
    assume allocator := system.page_allocator
    values ::= unwrap_or_abort(DynamicArray#(UInt8)(.allocator = allocator, .capacity = 1))
    push_assume_capacity($&values, .value = 7)

    if length(system.args).count > 1 {
        replacement ::= unwrap_or_abort(DynamicArray#(UInt8)(.allocator = allocator, .capacity = 2))
        for byte in values { push_assume_capacity($&replacement, .value = byte) }
        deinit(.self = $&values)
        values = ~replacement
    }

    for byte in values { if byte != 7 { abort } }
}
