A#(.Participant: Type): Contract = (.read: (.self: &Participant) -> (.value: Int32) where {})

Box: Type = (.value: Int32)

implement A#(Box) (.read = _impl_read_Box)

_impl_read_Box := (.self: &Box) -> (.value: Int32)  { value = self&.value }

main() -> (.status_code: Int32) := {
    box :: Box = (.value = 1)
    virtual ::= to_virtual#(.contract: A)(.value = $&box)
    if virtual.data | convert#(.to: UIntNative)(_) == $&box | convert#(.to: UIntNative)(_) {
        status_code = 0
    }
}
