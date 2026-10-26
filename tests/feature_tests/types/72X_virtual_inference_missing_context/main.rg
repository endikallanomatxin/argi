Counter<.Participant: Type>: Contract = (.bump: (.self: $&Participant) -> () where {})

Other<.Participant: Type>: Contract = ()

Probe := (.value: UIntNative = 0)

implement Counter<Probe> (.bump = _impl_bump_Probe)

implement Other<Probe> ()

_impl_bump_Probe := (.self: $&Probe) -> () { self&.value = self&.value + 1 }

main := () -> (.status_code: Int32) {
    probe ::= Probe()
    handle ::= to_virtual($&probe)
    status_code = 0
}
