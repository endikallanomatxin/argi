main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(
        .value = DynamicArray#(.t: UIntNative)(
            .allocator = system.page_allocator, .capacity = 4
        )
    )
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    iterator ::= to_reference_iterator(.value = &array).iterator
    element ::= next(.self = $&iterator).value
    removed ::= unwrap_or_abort(.value = pop(.self = $&array).result)
    observed ::= element&
    deinit(.self = $&array)
}
