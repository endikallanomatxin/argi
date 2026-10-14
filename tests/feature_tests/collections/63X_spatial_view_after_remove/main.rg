window(.array: $&DynamicArray#(.t: UIntNative)) -> (.borrowed_view: ArrayViewRO#(.t: UIntNative)) := {
    full ::= view(.array = array)
    borrowed_view = unwrap_or_abort(.value = slice#(.t: UIntNative)(.self = &full, .start = 0, .count = 1).result)
}
read_window(.borrowed_view: &ArrayViewRO#(.t: UIntNative)) -> (.value: UIntNative) := {
    element ::= unwrap_or_abort(.value = get_ro_ref(.self = borrowed_view, .index = 0).result)
    value = element&
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 2))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    borrowed_view ::= window(.array = $&array).borrowed_view
    removed ::= unwrap_or_abort(.value = remove(.self = $&array, .i = 0).result)
    observed ::= read_window(.borrowed_view = &borrowed_view).value
    deinit( .self = $&array)
}
