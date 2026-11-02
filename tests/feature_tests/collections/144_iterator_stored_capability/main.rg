Probe := (.calls: UIntNative = 0)

Sequence := (.remaining: Int32, .probe: $&Probe)

tick := (.probe: $&Probe) -> () {
    probe&.calls = probe&.calls + 1
}

implement Iterable#(Sequence) (
    .Item         : Type = Int32
    .IteratorType : Type = Sequence
    .to_iterator  = (.value: &Sequence) -> (.iterator: Sequence) {
        tick(.probe = value&.probe)
        iterator = (.remaining = value&.remaining, .probe = value&.probe)
    }
)

implement Iterator#(Sequence) (
    .Item     : Type = Int32
    .has_next = (.self: &Sequence) -> (.ok: Bool) {
        tick(.probe = self&.probe)
        ok = self&.remaining > 0
    }
    .next = (.self: $&Sequence) -> (.value: Int32) {
        tick(.probe = self&.probe)
        value = self&.remaining
        self&.remaining = self&.remaining - 1
    }
)

concrete_walk := (.sequence: &Sequence) -> (.sum: Int32 = 0) {
    for item in sequence { sum = sum + item }
}

generic_walk := #(.Collection: Type) (.sequence: &Collection) -> (.sum: Int32 = 0) {
    for item in sequence { sum = sum + item }
}

main := () -> () {
    concrete_probe :: Probe = (.calls = 0)
    sequence :: Sequence = (.remaining = 2, .probe = $&concrete_probe)
    if concrete_walk(.sequence = &sequence).sum != 3 { abort }
    if concrete_probe.calls != 6 { abort }
    generic_probe :: Probe = (.calls = 0)
    generic_sequence :: Sequence = (.remaining = 2, .probe = $&generic_probe)
    if generic_walk(.sequence = &generic_sequence).sum != 3 { abort }
    if generic_probe.calls != 6 { abort }
}
