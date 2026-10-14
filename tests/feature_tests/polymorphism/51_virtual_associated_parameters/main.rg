Readable#(.Participant: Type): Contract = (
    .item: Type

    .read: (.self: &Participant) -> (.value: item) where {}
)

Box: Type = (.value: Int32)

implement Readable#(Box) (.item: Type = Int32, .read = _impl_read_Box)

_impl_read_Box := (.self: &Box) -> (.value: Int32)  { value = self&.value }

consume(.input: &Virtual#(.abstract: Readable#(.item: Int32))) -> (.value: Int32) := {
    value = read(.self = input)
}

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: Readable#(.item: Int32))(.value = &box)
    if consume(.input = &handle).value != 7 { abort }
}
