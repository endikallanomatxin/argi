Owner := (.value: Int32)
implement Transferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { if self&.value != 42 { abort } }
)
produce := () -> (.owner: Owner) {
    owner = Owner(42)
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    owner :: Owner
    {
        task ::= unwrap_or_abort(async_owned#(produce)(.args = (), .executor = executor, .ffi = system.ffi))
        owner = unwrap_or_abort(await($&task))
        match await($&task) {
            ..ok ~unexpected { abort }
            ..error failure {
                if is(.value = failure.reason, .variant = ..already_awaited) == false { abort }
            }
        }
    }
    if owner.value != 42 { abort }
}
