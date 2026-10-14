A#(.Participant: Type): Contract = (.consume: (.self: Participant) -> () where {})

Box: Type = (.value: Int32)

implement A#(Box) (.consume = _impl_consume_Box)

_impl_consume_Box := (.self: Box) -> ()  {}

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
