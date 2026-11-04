write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    saved :: ?Future#(Void) = ..none
    index :: Int32 = 0
    while index < 2 {
        local :: Int32 = index
        future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&local)))
        saved = ..some(.value = ~future)
        index = index + 1
    }
    _ = ~saved
}
