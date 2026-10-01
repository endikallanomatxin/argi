Descending : Type = ()
Descending implements OrderPolicy#(.t: Int32)
less(.self: &Descending, .left: Int32, .right: Int32) -> (.ok: Bool) := { ok = left > right }
check_sorted(.self: &Indexable#(.t: Int32), .order: &OrderPolicy#(.t: Int32)) -> () := {
    count ::= length(.self = self).count
    index :: UIntNative = 1
    while index < count {
        before ::= unwrap_or_abort(.value = get_ro_ref(.self = self, .index = index - 1))&
        current ::= unwrap_or_abort(.value = get_ro_ref(.self = self, .index = index))&
        if less(.self = order, .left = current, .right = before).ok { abort }
        index = index + 1
    }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    order ::= Int32OrderPolicy()
    descending ::= Descending()
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 8))
    sort(.self = $&array, .order = &order)
    push_assume_capacity(.self = $&array, .value = 42)
    sort(.self = $&array, .order = &order)
    push_assume_capacity(.self = $&array, .value = -10)
    push_assume_capacity(.self = $&array, .value = 42)
    push_assume_capacity(.self = $&array, .value = 7)
    push_assume_capacity(.self = $&array, .value = 0)
    push_assume_capacity(.self = $&array, .value = 1)
    push_assume_capacity(.self = $&array, .value = -10)
    push_assume_capacity(.self = $&array, .value = 9)
    borrowed ::= unwrap_or_abort(.value = get_ro_ref(.self = &array, .index = 0))
    view ::= array_view(.array = $&array).view
    sort(.self = $&array, .order = &order)
    check_sorted(.self = &view, .order = &order)
    if borrowed& != -10 or length(.self = &array).count != 8 { abort }
    if unwrap_or_abort(.value = get(.self = &array, .index = 1)) != -10 { abort }
    if unwrap_or_abort(.value = get(.self = &array, .index = 6)) != 42 { abort }
    if unwrap_or_abort(.value = get(.self = &array, .index = 7)) != 42 { abort }
    sort(.self = $&view, .order = &descending)
    check_sorted(.self = &array, .order = &descending)
    if borrowed& != 42 { abort }
    match binary_search(.self = &array, .value = 42, .order = &descending).index {
        ..none { abort }
        ..some found { if found.value != 0 { abort } }
    }
    deinit(.self = $&array)
    fixed : [5]Int32 = (99, 3, 1, 2, -99)
    fixed_view ::= array_view(.array = $&fixed).view
    middle ::= unwrap_or_abort(.value = slice(.self = &fixed_view, .start = 1, .count = 3))
    sort(.self = $&middle, .order = &order)
    if fixed[0] != 99 or fixed[1] != 1 or fixed[2] != 2 or fixed[3] != 3 or fixed[4] != -99 { abort }
    empty : [0]Int32 = ()
    empty_view ::= array_view(.array = $&empty).view
    sort(.self = $&empty_view, .order = &order)
}
