read(.items: &IndexableValue#(.t: Int32), .index: UIntNative) -> (.value: Int32) := {
    value = unwrap_or_abort(.value = get(.self = items, .index = index))
}
borrow(.items: &Indexable#(.t: Int32)) -> (.value: Int32) := {
    pointer ::= unwrap_or_abort(.value = get_ro_ref(.self = items, .index = 0))
    value = pointer&
}
write(.items: $&IndexableMutable#(.t: Int32)) -> () := {
    pointer ::= unwrap_or_abort(.value = get_rw_ref(.self = items, .index = 0))
    pointer& = 9
}
resize(.items: $&Resizable#(.t: Int32), .allocator: $&Allocator) -> (.value: Int32) := {
    unwrap_or_abort(.value = push(.self = items, .value = 3, .allocator = allocator))
    unwrap_or_abort(.value = insert(.self = items, .i = 0, .value = 4, .allocator = allocator))
    removed ::= unwrap_or_abort(.value = remove(.self = items, .i = 0))
    popped ::= unwrap_or_abort(.value = pop(.self = items))
    value = removed + popped
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&storage
    dynamic ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 2))
    if resize(.items = $&dynamic, .allocator = allocator).value != 7 { abort }
    unwrap_or_abort(.value = push(.self = $&dynamic, .value = 2))
    write(.items = $&dynamic)
    if read(.items = &dynamic, .index = 0).value != 9 { abort }
    if borrow(.items = &dynamic).value != 9 { abort }
    values : [2]Int32 = (5, 6)
    view ::= array_view(.array = $&values)
    write(.items = $&view)
    if read(.items = &view, .index = 0).value != 9 { abort }
    if borrow(.items = &view).value != 9 { abort }
    readonly ::= array_view_ro(.array = &values)
    if read(.items = &readonly, .index = 1).value != 6 { abort }
    if borrow(.items = &readonly).value != 9 { abort }
    if is(.value = get(.self = &readonly, .index = 2).result, .variant = ..ok) { abort }
}
