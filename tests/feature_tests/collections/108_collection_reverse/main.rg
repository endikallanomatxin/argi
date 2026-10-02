main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 5))
    reverse(.self = $&array)
    push_assume_capacity(.self = $&array, .value = 1)
    reverse(.self = $&array)
    if unwrap_or_abort(.value = get(.self = &array, .index = 0)) != 1 { abort }
    push_assume_capacity(.self = $&array, .value = 2)
    push_assume_capacity(.self = $&array, .value = 3)
    push_assume_capacity(.self = $&array, .value = 4)
    push_assume_capacity(.self = $&array, .value = 5)
    borrowed ::= unwrap_or_abort(.value = get_ro_ref(.self = &array, .index = 0))
    view ::= array_view(.array = $&array).view
    reverse(.self = $&array)
    if borrowed& != 5 { abort }
    if unwrap_or_abort(.value = get(.self = &view, .index = 4)) != 1 { abort }
    reverse(.self = $&view)
    if borrowed& != 1 { abort }
    if length(.self = &array).count != 5 { abort }
    deinit(.self = $&array)
    fixed : [4]Int32 = (10, 20, 30, 40)
    fixed_view ::= array_view(.array = $&fixed).view
    middle ::= unwrap_or_abort(.value = slice(.self = &fixed_view, .start = 1, .count = 2))
    reverse(.self = $&middle)
    if fixed[0] != 10 or fixed[1] != 30 or fixed[2] != 20 or fixed[3] != 40 { abort }
    reverse(.self = $&fixed_view)
    if fixed[0] != 40 or fixed[1] != 20 or fixed[2] != 30 or fixed[3] != 10 { abort }
    empty : [0]Int32 = ()
    empty_view ::= array_view(.array = $&empty).view
    reverse(.self = $&empty_view)
}
