Editor#(.Participant: Type): Contract = (
    .edit : (.self: &Participant, .target: $&Int32, .succeed: Bool) -> (.result: ?Int32) where {
        on result ..some { invalidates(target) }
        on result ..none {}
    }
)

Cell := (.unused: Int32)

implement Editor#(Cell) (.edit = _impl_edit_Cell)

_impl_edit_Cell := (.self: &Cell, .target: $&Int32, .succeed: Bool) -> (.result: ?Int32) {
    if succeed {
        target&= 42
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

apply_edit := (.editor: &Virtual#(Editor), .target: $&Int32, .succeed: Bool) -> (.result: ?Int32) {
    result = edit(editor, target, succeed)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    target :: Int32 = 41
    previous ::= &target
    editor ::= to_virtual#(Editor)(&cell)
    result ::= apply_edit(&editor, $&target, false)

    target = 99

    match result {
        ..none { if previous&!= 99 { status_code = 1 } }
        ..some _ { status_code = 2 }
    }
}
