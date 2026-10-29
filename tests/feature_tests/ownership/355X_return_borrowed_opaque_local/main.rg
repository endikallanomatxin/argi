escape := (.array: $&DynamicArray#(&Int32)) -> (.result: $&DynamicArray#(&Int32)) {
    local :: Int32 = 7
    push_assume_capacity(array, &local)
    result = array
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    array ::= unwrap_or_abort(DynamicArray#(&Int32)(.capacity = 1))
    escaped ::= escape($&array)
}
