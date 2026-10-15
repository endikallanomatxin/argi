Probe: Type = (.calls: UIntNative = 0)

Sequence: Type = (.remaining: Int32)

tick(.probe: $&Probe = reach probe) -> () := {
    probe&.calls = probe&.calls + 1
}

implement Iterable#(Sequence) (
    .Item         : Type = Int32
    .IteratorType : Type = Sequence
    .to_iterator  = (.value: &Sequence) -> (.iterator: Sequence) {
        tick()
        iterator = (.remaining = value&.remaining)
    }
)

implement Iterator#(Sequence) (
    .Item     : Type = Int32
    .has_next = (.self: &Sequence) -> (.ok: Bool) {
        tick()
        ok = self&.remaining > 0
    }
    .next = (.self: $&Sequence) -> (.value: Int32) {
        tick()
        value = self&.remaining
        self&.remaining = self&.remaining - 1
    }
)

concrete_walk(.sequence: &Sequence, .probe: $&Probe) -> (.sum: Int32 = 0) := {
    assume probe
    for item in sequence { sum = sum + item }
}

generic_walk#(.Collection: Type)(.sequence: &Collection, .probe: $&Probe) -> (.sum: Int32 = 0) := {
    assume probe
    for item in sequence { sum = sum + item }
}

main() -> () := {
    sequence :: Sequence = (.remaining = 2)
    concrete_probe :: Probe = (.calls = 0)
    if concrete_walk(.sequence = &sequence, .probe = $&concrete_probe).sum != 3 { abort }
    if concrete_probe.calls != 6 { abort }
    generic_probe :: Probe = (.calls = 0)
    if generic_walk(.sequence = &sequence, .probe = $&generic_probe).sum != 3 { abort }
    if generic_probe.calls != 6 { abort }
}
