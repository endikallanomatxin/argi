write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 0
    address ::= &value | convert#(.to: UIntNative)(_)
    pointer ::= trusted_establish_inherited_reference#(Int32)(
        .raw = raw_pointer#(Int32)(.address = address),
        .root = erase_reference#(Int32)(.base = &value)
    )
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    _ = unwrap_or_abort(.value = await($&future))
    if pointer& != 42 { abort }
}
