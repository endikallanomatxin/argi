Witness := (.marker: UInt8)
implement Deinit#(Witness) (
    .deinit = (.self: $&Witness) -> () {}
)
under_witness := #(.T: Type) (.base: &T, .witness: &Any) -> (.reference: &T) {
    reference = restrict_reference#(.t: &T)(.input = base, .on = witness)
}
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    first: Witness = (.marker = 0)
    second: Witness = (.marker = 1)
    value :: Int32 = 42
    a ::= under_witness#(Int32)(.base = &value, .witness = &first)
    b ::= under_witness#(Int32)(.base = &value, .witness = &second)
    first_future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = a)))
    second_future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = b)))
    _ = unwrap_or_abort(.value = await($&first_future))
    deinit(.self = $&second)
    _ = unwrap_or_abort(.value = await($&second_future))
}
