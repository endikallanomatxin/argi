Record : Type = (.key: Int32, .tag: Int32)
Record implements ImplicitlyCopyable
ByKey : Type = ()
ByKey implements OrderPolicy#(.t: Record)
less(.self: &ByKey, .left: Record, .right: Record) -> (.ok: Bool) := { ok = left.key < right.key }
Descending : Type = ()
Descending implements OrderPolicy#(.t: Int32)
less(.self: &Descending, .left: Int32, .right: Int32) -> (.ok: Bool) := { ok = left > right }
expect_index(.result: ?UIntNative, .expected: UIntNative) -> () := {
    match result {
        ..none { abort }
        ..some entry { if entry.value != expected { abort } }
    }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    order ::= Int32OrderPolicy()
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 6))
    if is(.value = binary_search(.self = &array, .value = 1, .order = &order).index, .variant = ..some) { abort }
    push_assume_capacity(.self = $&array, .value = -10)
    push_assume_capacity(.self = $&array, .value = 2)
    push_assume_capacity(.self = $&array, .value = 2)
    push_assume_capacity(.self = $&array, .value = 2)
    push_assume_capacity(.self = $&array, .value = 9)
    push_assume_capacity(.self = $&array, .value = 20)
    expect_index(.result = binary_search(.self = &array, .value = -10, .order = &order).index, .expected = 0)
    expect_index(.result = binary_search(.self = &array, .value = 2, .order = &order).index, .expected = 1)
    found ::= binary_search(.self = &array, .value = 20, .order = &order).index
    expect_index(.result = found, .expected = 5)
    if is(.value = binary_search(.self = &array, .value = -11, .order = &order).index, .variant = ..some) { abort }
    if is(.value = binary_search(.self = &array, .value = 8, .order = &order).index, .variant = ..some) { abort }
    if is(.value = binary_search(.self = &array, .value = 21, .order = &order).index, .variant = ..some) { abort }
    deinit(.self = $&array)
    expect_index(.result = found, .expected = 5)
    descending ::= Descending()
    fixed : [5]Int32 = (9, 5, 5, 3, 1)
    view ::= array_view_ro(.array = &fixed).view
    expect_index(.result = binary_search(.self = &view, .value = 5, .order = &descending).index, .expected = 1)
    records : [3]Record = ((.key = 1, .tag = 10), (.key = 1, .tag = 20), (.key = 2, .tag = 30))
    records_view ::= array_view_ro(.array = &records).view
    by_key ::= ByKey()
    target :: Record = (.key = 1, .tag = 999)
    expect_index(.result = binary_search(.self = &records_view, .value = target, .order = &by_key).index, .expected = 0)
    text : [3]StringView = ("", "a", "ab")
    text_view ::= array_view_ro(.array = &text).view
    text_order ::= StringViewOrderPolicy()
    bytes : [1]UInt8 = (97)
    needle :: StringView = (.data = &bytes[0], .length = 1)
    expect_index(.result = binary_search(.self = &text_view, .value = needle, .order = &text_order).index, .expected = 1)
}
