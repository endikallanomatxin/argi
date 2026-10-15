window(.array: $&DynamicArray#(.t: UIntNative)) -> (.borrowed_view: MutableArrayView#(.t: UIntNative)) := {
    full ::= view(.array = array)
    borrowed_view = unwrap_or_abort(.value = slice(.self = &full, .start = 0, .count = 1).result)
}
read_window(.borrowed_view: &MutableArrayView#(.t: UIntNative)) -> (.value: UIntNative) := {
    value = unwrap_or_abort(.value = get(.self = borrowed_view, .index = 0).result)
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    arena :: ArenaAllocator
    arena = unwrap_or_abort(.value = ArenaAllocator(.allocator = system.page_allocator))
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UIntNative)(.allocator = $&arena, .capacity = 2))
    push_assume_capacity#(.t: UIntNative)(.self = $&array, .value = 7)
    borrowed_view ::= window(.array = $&array).borrowed_view
    reset(.self = $&arena)
    observed ::= read_window(.borrowed_view = &borrowed_view).value
}
