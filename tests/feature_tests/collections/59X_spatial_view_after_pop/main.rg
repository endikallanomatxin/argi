window(.array: $&DynamicArray#(.t: UIntNative)) -> (.view: ArrayView#(.t: UIntNative)) := {
    full ::= array_view#(.t: UIntNative)(.array = array).view
    alias ::= &full
    view = unwrap_or_abort(.value = slice#(.t: UIntNative)(.self = alias, .start = 0, .count = 1).result)
}
read_window(.view: &ArrayView#(.t: UIntNative)) -> (.value: UIntNative) := {
    value = unwrap_or_abort(.value = get#(.t: UIntNative)(.self = view, .index = 0).result)
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 2))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    view ::= window(.array = $&array).view
    removed ::= unwrap_or_abort(.value = pop#(.t: UIntNative)(.self = $&array).result)
    observed ::= read_window(.view = &view).value
    deinit#(.t: UIntNative)(.allocator = system.page_allocator, .self = $&array)
}
