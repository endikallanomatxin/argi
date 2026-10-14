window(.array: $&DynamicArray#(.t: UIntNative)) -> (.borrowed_view: ArrayView#(.t: UIntNative)) := {
    full ::= view(.array = array)
    alias ::= &full
    borrowed_view = unwrap_or_abort(.value = slice(.self = alias, .start = 0, .count = 1).result)
}
read_window(.borrowed_view: &ArrayView#(.t: UIntNative)) -> (.value: UIntNative) := {
    value = unwrap_or_abort(.value = get(.self = borrowed_view, .index = 0).result)
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 2))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    borrowed_view ::= window(.array = $&array).borrowed_view
    removed ::= unwrap_or_abort(.value = pop(.self = $&array).result)
    observed ::= read_window(.borrowed_view = &borrowed_view).value
    deinit( .self = $&array)
}
