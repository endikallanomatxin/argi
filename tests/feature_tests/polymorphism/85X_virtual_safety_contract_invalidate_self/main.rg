Editor#(.Participant: Type): Contract = (
    .edit : (.self: $&Participant) -> () where invalidates(self)
)

Cell := (.unused: Int32)

implement Editor#(Cell) (.edit = _impl_edit_Cell)

_impl_edit_Cell := (.self: $&Cell) -> () {}

main := () -> () {
    cell ::= Cell(0)
    editor ::= to_virtual#(Editor)($&cell)
}
