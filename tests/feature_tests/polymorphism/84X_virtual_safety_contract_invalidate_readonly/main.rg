Editor#(.Participant: Type): Contract = (
    .edit: (.self: &Participant, .target: &Int32) -> ()
    where invalidates(target)
)

Cell: Type = (.unused: Int32)

implement Editor#(Cell) (.edit = _impl_edit_Cell)

_impl_edit_Cell := (.self: &Cell, .target: &Int32) -> ()  {

}

apply_edit(.editor: &Virtual#(Editor), .target: &Int32) -> () := {
    edit(editor, target)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(0)
    target :: Int32 = 41
    editor ::= to_virtual#(Editor)(&cell)
    apply_edit(&editor, $&target)

    if target != 42 {
        status_code = 1
    }
}
