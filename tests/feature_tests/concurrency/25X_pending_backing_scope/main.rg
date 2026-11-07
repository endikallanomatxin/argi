read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    saved :: ?Future#(Int32) = ..none
    {
        local :: Int32 = 42
        future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &local)))
        saved = ..some(.value = ~future)
    }
    match ~saved {
        ..some ~entry {
            moved ::= ~entry.value
        }
        ..none { abort }
    }
}
