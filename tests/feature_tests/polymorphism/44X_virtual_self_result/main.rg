A#(.Participant: Type): Contract = (.borrow: (.self: &Participant) -> (.value: &Participant) where depends_on(value, self))

Box: Type = (.value: Int32)

implement A#(Box) (.borrow = _impl_borrow_Box)

_impl_borrow_Box := (.self: &Box) -> (.value: &Box)  { value = self }

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
