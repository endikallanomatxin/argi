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
    witness: Witness = (.marker = 0)
    value :: Int32 = 42
    reference ::= under_witness#(Int32)(.base = &value, .witness = &witness)
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = reference)))
    _ = unwrap_or_abort(.value = await($&future))
    deinit(.self = $&witness)
    witness = (.marker = 1)
    stale ::= unwrap_or_abort(.value = async#(read)(.args = (.value = reference)))
    _ = unwrap_or_abort(.value = await($&stale))
}
