read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 0
    address ::= &value | convert#(.to: UIntNative)(_)
    pointer ::= trusted_establish_inherited_reference#(Int32)(
        .raw = raw_pointer#(Int32)(.address = address),
        .root = erase_reference#(Int32)(.base = &value)
    )
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    pointer& = 42
    _ = unwrap_or_abort(.value = await($&future))
}
