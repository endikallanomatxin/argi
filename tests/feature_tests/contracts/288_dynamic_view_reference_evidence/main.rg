borrow := #(.Source: Type: Viewable#(Source)) (.array: Source) -> (
    .result : Viewable#(Source).Result
) {
    result = view(.self = array)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator ::= system.page_allocator
    values ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 2))
    empty ::= borrow(.array = &values)
    unwrap_or_abort(.value = push(.self = $&values, .value = 7))
    if length(&empty) != 0 { status_code = 1 }
    mutable ::= borrow(.array = $&values)
    pointer ::= unwrap_or_abort(.value = get_mutable_reference(.self = $&mutable, .index = 0))
    pointer&= 42
    readonly ::= borrow(.array = &values)
    if unwrap_or_abort(.value = get_reference(.self = &readonly, .index = 0))&!= 42 {
        status_code = 2
    }
    scalar :: Int32 = 9
    single ::= single_array_view(.data = &scalar)
    if length(&single) != 1 { status_code = 3 }
}
