A#(.Participant: Type): Contract = (.inspect: (.self: &Participant, .nested: (.value: &Participant)) -> () where {})

Box: Type = (.value: Int32)

implement A#(Box) (.inspect = _impl_inspect_Box)

_impl_inspect_Box := (.self: &Box, .nested: (.value: &Box)) -> ()  {}

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
