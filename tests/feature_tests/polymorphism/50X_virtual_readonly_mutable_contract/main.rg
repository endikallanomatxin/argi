Counter#(.Participant: Type): Contract = (.bump: (.self: $&Participant) -> () where {})

Box: Type = (.value: Int32)

implement Counter#(Box) (.bump = _impl_bump_Box)

_impl_bump_Box := (.self: $&Box) -> ()  { self&.value = self&.value + 1 }

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    readonly ::= &box
    handle ::= to_virtual#(.abstract: Counter)(.value = readonly)
    bump(.self = $&handle)
}
