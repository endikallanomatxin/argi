Probe#(.R: Type): Contract = (
    .read: (.receiver: R) -> (.value: Int32) where {}
)

Witness := (.ignored: Int32)
implement Probe#($&Witness) (
    .read = (.receiver: $&Witness) -> (.value: Int32) { value = 1 }
)

Observer := (.value: Int32)
implement Probe#($&Observer) (
    .read = (.receiver: $&Observer) -> (.value: Int32) { value = receiver&.value }
)

pair := (.one: Virtual#(Probe), .two: Virtual#(Probe)) -> (.sum: Int32) {
    sum = one.read().value + two.read().value
}

main := (.system: System) -> () {
    cell ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    shared ::= $$&cell
    first ::= Witness(0)
    second ::= Observer(1)
    one ::= Virtual#(Probe)($&first)
    two ::= Virtual#(Probe)($&second)
    if pair(.one = one, .two = two) != 2 { abort }
    if shared_load(.self = shared) != 0 { abort }
    recover_ordinary(.owner = $&cell)
}
