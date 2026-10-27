check_order := #(.t: Type: ImplicitlyCopyable, .policy: Type: OrderPolicy#(policy, t)) (
    .order: &policy, .left: t, .right: t
) -> () {
    if OrderPolicy#(policy, t).less(.self = order, .left = &left, .right = &right).ok == false {
        abort
    }
    if OrderPolicy#(policy, t).less(.self = order, .left = &right, .right = &left).ok { abort }
    if OrderPolicy#(policy, t).less(.self = order, .left = &left, .right = &left).ok { abort }
}

Descending: Type = ()

implement OrderPolicy#(Descending, Int32) (
    .less = (.self: &Descending, .left: &Int32, .right: &Int32) -> (.ok: Bool) {
        ok = left&> right&
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    integers ::= Int32OrderPolicy()
    check_order(.order = &integers, .left = -2147483648, .right = 2147483647)
    native ::= UIntNativeOrderPolicy()
    zero :: UIntNative = 0
    last :: UIntNative = 123
    check_order(.order = &native, .left = zero, .right = last)
    descending ::= Descending()
    check_order(.order = &descending, .left = 20, .right = 10)
    text ::= StringViewOrderPolicy()
    check_order(.order = &text, .left = "", .right = "a")
    check_order(.order = &text, .left = "a", .right = "aa")
    check_order(.order = &text, .left = "ab", .right = "b")
    bytes: [3]UInt8 = (97, 0, 98)
    same: [3]UInt8 = (97, 0, 98)
    left_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&bytes), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    left ::= view(&left_storage)
    right_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&same), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    right ::= view(&right_storage)
    if OrderPolicy#(StringViewOrderPolicy, StringView).less(
        .self = &text, .left = &left, .right = &right
    ).ok { abort }
    if OrderPolicy#(StringViewOrderPolicy, StringView).less(
        .self = &text, .left = &right, .right = &left
    ).ok { abort }
    check_order(.order = &text, .left = left, .right = "ab")
}
