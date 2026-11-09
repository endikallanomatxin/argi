Transform(.value: CInt) -> (.result: CInt): CFunctionPointer
twice := (.value: CInt) -> (.result: CInt): CFunction { result = value * 2 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    assume ffi := system.ffi
    provider ::= ThreadedExecutor(.ffi = ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    callback ::= Transform(.function = twice)
    _ = callback(.value = 21)
}
