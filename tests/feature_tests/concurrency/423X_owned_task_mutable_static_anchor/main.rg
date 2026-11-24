static_anchor :: Int32 = 42

Owner := (._anchor: &Any, ._value: &Int32)

implement StructurallyTransferable#(Owner) ()

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {}
)

make_owner := (.value: &Int32) -> (.owner: Owner) {
    anchor ::= erase_reference#(Int32)(.base = value).reference
    owner = Owner(._anchor = anchor, ._value = value)
}

read := (.owner: Owner) -> (.value: Int32) {
    held ::= ~owner
    value = held._value&
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    owner ::= make_owner(.value = &static_anchor)
    task ::= unwrap_or_abort(async_owned#(read)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 42 { abort }
}
