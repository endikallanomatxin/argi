Record := (.key: Int32, .tag: Int32)

implement ImplicitlyCopyable#(Record) ()

ByKey: Type = ()

implement OrderPolicy#(ByKey, Record) (
    .less = (.self: &ByKey, .left: &Record, .right: &Record) -> (.ok: Bool) {
        ok = [left&.key < right&.key]
    }
)

Descending: Type = ()

implement OrderPolicy#(Descending, Int32) (
    .less = (.self: &Descending, .left: &Int32, .right: &Int32) -> (.ok: Bool) {
        ok = left&> right&
    }
)

expect_index := (.result: ?UIntNative, .expected: UIntNative) -> () {
    match result {
        ..none { abort }
        ..some entry { if entry.value != expected { abort } }
    }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= system.page_allocator
    order ::= Int32OrderPolicy()
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 6))
    if is(
        .value   = binary_search(.self = &array, .value = 1, .order = &order).index
        .variant = ..some
    ) { abort }
    push_assume_capacity(.self = $&array, .value = -10)
    push_assume_capacity(.self = $&array, .value = 2)
    push_assume_capacity(.self = $&array, .value = 2)
    push_assume_capacity(.self = $&array, .value = 2)
    push_assume_capacity(.self = $&array, .value = 9)
    push_assume_capacity(.self = $&array, .value = 20)
    expect_index(
        .result   = binary_search(.self = &array, .value = -10, .order = &order).index
        .expected = 0
    )
    expect_index(
        .result   = binary_search(.self = &array, .value = 2, .order = &order).index
        .expected = 1
    )
    found ::= binary_search(.self = &array, .value = 20, .order = &order).index
    expect_index(.result = found, .expected = 5)
    if is(
        .value   = binary_search(.self = &array, .value = -11, .order = &order).index
        .variant = ..some
    ) { abort }
    if is(
        .value   = binary_search(.self = &array, .value = 8, .order = &order).index
        .variant = ..some
    ) { abort }
    if is(
        .value   = binary_search(.self = &array, .value = 21, .order = &order).index
        .variant = ..some
    ) { abort }
    deinit(.self = $&array)
    expect_index(.result = found, .expected = 5)
    descending ::= Descending()
    fixed: [5]Int32 = (9, 5, 5, 3, 1)
    borrowed_view ::= view(.self = &fixed)
    expect_index(
        .result = binary_search(
            .self = &borrowed_view, .value = 5, .order = &descending
        ).index
        .expected = 1
    )
    records: [3]Record = ((.key = 1, .tag = 10), (.key = 1, .tag = 20), (.key = 2, .tag = 30))
    records_view ::= view(.self = &records)
    by_key ::= ByKey()
    target :: Record = (.key = 1, .tag = 999)
    expect_index(
        .result = binary_search(
            .self = &records_view, .value = target, .order = &by_key
        ).index
        .expected = 0
    )
    text: [3]StringView = ("", "a", "ab")
    text_view ::= view(.self = &text)
    text_order ::= StringViewOrderPolicy()
    bytes: [1]UInt8 = (97)
    needle_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&bytes), .start = 0, .count = 1))
            .allocator = system.page_allocator
        )
    )
    needle ::= view(&needle_storage)
    expect_index(
        .result = binary_search(
            .self = &text_view, .value = needle, .order = &text_order
        ).index
        .expected = 1
    )
}
