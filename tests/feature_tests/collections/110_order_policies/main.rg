check_order#(
        .t      : Type: ImplicitlyCopyable,
        .policy : Type: OrderPolicy#(policy, t)
    )(
        .order : &policy,
        .left  : t,
        .right : t
    ) -> () := {
    if OrderPolicy#(policy, t).less(.self = order, .left = left, .right = right).ok == false {
        abort
    }
    if OrderPolicy#(policy, t).less(.self = order, .left = right, .right = left).ok { abort }
    if OrderPolicy#(policy, t).less(.self = order, .left = left, .right = left).ok { abort }
}

Descending: Type = ()

implement OrderPolicy#(Descending, Int32)(
    .less = (.self: &Descending, .left: Int32, .right: Int32) -> (.ok: Bool) { ok = left > right }
)

main() -> (.status_code: Int32 = 0) := {
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
    left :: StringView = (.data = &bytes[0], .length = 3)
    right :: StringView = (.data = &same[0], .length = 3)
    if OrderPolicy#(StringViewOrderPolicy, StringView).less(
        .self  = &text
        .left  = left
        .right = right
    ).ok { abort }
    if OrderPolicy#(StringViewOrderPolicy, StringView).less(
        .self  = &text
        .left  = right
        .right = left
    ).ok { abort }
    check_order(.order = &text, .left = left, .right = "ab")
}
