Counter#(.Participant: Type): Contract = (.bump: (.self: $&Participant) -> () where {})

Probe: Type = (.value: UIntNative = 0)

implement Counter#(Probe) (.bump = _impl_bump_Probe)

_impl_bump_Probe := (.self: $&Probe) -> ()  { self&.value = self&.value + 1 }

escape() -> (.handle: $&Virtual#(.abstract: Counter)) := {
    handle = Probe() | to_virtual($&_) | $&_
}

main() -> (.status_code: Int32) := {
    handle ::= escape()
    bump(.self = handle)
    status_code = 0
}
