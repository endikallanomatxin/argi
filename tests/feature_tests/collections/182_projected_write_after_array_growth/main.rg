Item := (.reversed: Bool, .edge: UIntNative)
main := (.system: System) -> () {
    assume allocator := system.page_allocator
    count ::= length(system.args).count
    items ::= unwrap_or_abort(DynamicArray#(Item)(.allocator = allocator, .capacity = count))
    i :: UIntNative = 0
    while i < count {
        unwrap_or_abort(push($&items, .value = Item(.reversed = false, .edge = i)))
        i = i + 1
    }
    item ::= unwrap_or_abort(get_mutable_reference($&items, .index = 0))
    item&.reversed = true
    if item&.reversed == false { abort }
}
