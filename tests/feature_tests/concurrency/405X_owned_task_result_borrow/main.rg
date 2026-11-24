anchor: Int32 = 42
Owner := (.value: &Int32)
implement Transferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { if self&.value& != 42 { abort } }
)
produce := () -> (.owner: Owner) {
    owner = Owner(&anchor)
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    task ::= unwrap_or_abort(async_owned#(produce)(.args = (), .executor = executor, .ffi = system.ffi))
    owner ::= unwrap_or_abort(await($&task))
    if owner.value& != 42 { abort }
}
