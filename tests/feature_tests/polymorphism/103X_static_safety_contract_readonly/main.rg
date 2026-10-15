Editor#(.Participant: Type): Contract = (
    .edit: (.self: &Participant, .target: &Int32) -> () where invalidates(target)
)

Cell: Type = (.value: Int32)

implement Editor#(Cell) (.edit = _impl_edit_Cell)

_impl_edit_Cell := (.self: &Cell, .target: &Int32) -> ()  {}

main() -> () := {}
