read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    saved :: ?Future#(Int32) = ..none
    {
        local :: Int32 = 42
        future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &local)))
        if unwrap_or_abort(.value = await($&future)) != 42 { abort }
        saved = ..some(.value = ~future)
    }
    match ~saved {
        ..some ~entry {
            moved ::= ~entry.value
        }
        ..none { abort }
    }
}
