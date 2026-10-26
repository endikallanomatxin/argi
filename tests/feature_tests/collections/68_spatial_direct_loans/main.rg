loan := (.array: &DynamicArray<.t: UIntNative>) -> (.element: &UIntNative) {
    iterator ::= to_reference_iterator(.value = array).iterator
    element = next(.self = $&iterator).value
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    array ::= unwrap_or_abort(
        .value = DynamicArray<.t: UIntNative>(.allocator = system.page_allocator, .capacity = 4)
    )
    push_assume_capacity<.t: UIntNative> (.self = $&array, .value = 7)
    borrowed ::= loan(.array = &array).element
    if borrowed&!= 7 { status_code = 1 }
    mutable ::= unwrap_or_abort(
        .value = get_mutable_reference(.self = $&array, .index = 0).result
    )
    mutable&= 9
    if borrowed&!= 9 { status_code = 2 }
    removed ::= unwrap_or_abort(.value = pop(.self = $&array).result)
    push_assume_capacity<.t: UIntNative> (.self = $&array, .value = 11)
    fresh ::= unwrap_or_abort(.value = get_reference(.self = &array, .index = 0).result)
    if fresh&!= 11 { status_code = 3 }
    iterator ::= to_mutable_reference_iterator(.value = $&array).iterator
    element ::= next(.self = $&iterator).value
    element&= 13
    if fresh&!= 13 { status_code = 4 }
    deinit(.self = $&array)
}
