counter :: Int32 = 0
Owner := (.value: Int32)
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { counter = 42 }
)
work := () -> () { owner: Owner = (.value = 1) }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
    _ = unwrap_or_abort(.value = await($&future))
}
