write := (.value: $&Int32) -> () { value& = 42 }

at_base := (.base: &Int32) -> (.reference: &Int32) {
    reference = trusted_reference_offset#(.t: Int32)(.base = base, .elements = 0).reference
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    first: Int32 = 7
    second :: Int32 = 9
    selected ::= trusted_reference_offset#(.t: Int32)(.base = &first, .elements = 0).reference
    forwarded ::= at_base(&first)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&second)))
    if selected& != 7 { abort }
    if forwarded& != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if second != 42 { abort }
}
