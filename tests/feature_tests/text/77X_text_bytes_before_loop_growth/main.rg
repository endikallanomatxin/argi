main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    field ::= unwrap_or_abort(.value = DynamicArray#(UInt8)(.capacity = 1))
    unwrap_or_abort(.value = push($&field, .value = 65))
    old ::= view(&field)
    index :: UIntNative = 0
    while index < 2 {
        if index == 0 {
            unwrap_or_abort(.value = push($&field, .value = 66))
            index = index + 1
            continue
        }
        unwrap_or_abort(.value = push($&field, .value = 67))
        index = index + 1
    }
    _ ::= string_from_bytes(.bytes = old)
}
