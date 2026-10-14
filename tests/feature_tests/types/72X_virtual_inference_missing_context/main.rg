Counter#(.Participant: Type): Contract = (.bump: (.self: $&Participant) -> () where {})

Other: Abstract = ()

Probe: Type = (.value: UIntNative = 0)

implement Counter#(Probe) (.bump = _impl_bump_Probe)
Probe implements Other

_impl_bump_Probe := (.self: $&Probe) -> ()  { self&.value = self&.value + 1 }

main() -> (.status_code: Int32) := {
    probe ::= Probe()
    handle ::= to_virtual($&probe)
    status_code = 0
}
