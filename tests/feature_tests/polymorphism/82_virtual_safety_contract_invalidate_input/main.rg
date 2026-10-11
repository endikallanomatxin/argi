Editor: Abstract = (
    edit(.self: &Self, .target: $&Int32) -> ()
    where invalidates(target)
)

Cell: Type = (.unused: Int32)

Cell implements Editor

edit(.self: &Cell, .target: $&Int32) -> () := {
    target&= 42
}

apply_edit(.editor: &Virtual#(Editor), .target: $&Int32) -> () := {
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
