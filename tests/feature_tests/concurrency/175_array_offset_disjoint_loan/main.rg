write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    values :: [2]Int32 = (0, 0)
    first ::= $&values[0]
    second ::= trusted_mutable_reference_offset#(.t: Int32)(
        .base = $&values[0], .elements = 1
    ).reference
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = second)))
    first& = 9
    _ = unwrap_or_abort(.value = await($&future))
    if values[0] != 9 or values[1] != 42 { abort }
}
