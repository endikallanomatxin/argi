Owner := (.value: Int32)
drops :: Int32 = 0
implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })
consume := (.value: Owner) -> () { abort }
read := (.value: &Int32) -> (.result: Int32) { result = value& }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    owner ::= Owner(42)
    match async#(consume)(.args = (.value = ~owner)) {
        ..ok ~unexpected { abort }
        ..error _ {}
    }
    if drops != 1 { abort }
    value: Int32 = 42
    borrowed ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if unwrap_or_abort(.value = await($&borrowed)) != 42 { abort }
}
