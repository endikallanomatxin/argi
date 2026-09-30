window(.array: $&DynamicArray#(.t: UIntNative)) -> (.view: ArrayViewRO#(.t: UIntNative)) := {
    full ::= array_view_ro#(.t: UIntNative)(.array = array).view
    view = unwrap_or_abort(.value = slice#(.t: UIntNative)(.self = &full, .start = 0, .count = 1).result)
}
read_window(.view: &ArrayViewRO#(.t: UIntNative)) -> (.value: UIntNative) := {
    element ::= unwrap_or_abort(.value = get_ro_ref#(.t: UIntNative)(.self = view, .index = 0).result)
    value = element&
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = system.page_allocator, .capacity = 2))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    view ::= window(.array = $&array).view
    removed ::= unwrap_or_abort(.value = remove#(.t: UIntNative)(.self = $&array, .i = 0).result)
    observed ::= read_window(.view = &view).value
    deinit#(.t: UIntNative)(.allocator = system.page_allocator, .self = $&array)
}
