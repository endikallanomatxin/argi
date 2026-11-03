initial :: Int32 = 0
stored :: $&Int32 = $&initial
remember := (.value: $&Int32) -> () { stored = value }
work := () -> () { stored&= stored&+ 1 }
main := (.system: System) -> () {
    local :: Int32 = 0
    remember(.value = $&local)
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
    _ = future
}
