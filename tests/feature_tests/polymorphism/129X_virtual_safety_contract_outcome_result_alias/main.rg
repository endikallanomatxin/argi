Editor<.Participant: Type>: Contract = (
    .edit : (.self: &Participant, .target: $&Int32, .succeed: Bool) -> (.result: ?Int32) where {
        on result ..some { invalidates(target) }
        on result ..none {}
    }
)

Cell := (.unused: Int32)

implement Editor<Cell> (.edit = _impl_edit_Cell)

Resetter<.Participant: Type>: Contract = (
    .reset : (.self: &Participant, .target: $&Int32) -> () where invalidates(target)
)

implement Resetter<Cell> (.reset = _impl_reset_Cell)

_impl_reset_Cell := (.self: &Cell, .target: $&Int32) -> () { target&= 42 }

_impl_edit_Cell := (.self: &Cell, .target: $&Int32, .succeed: Bool) -> (.result: ?Int32) {
    resetter ::= to_virtual<Resetter>(self)
    reset(&resetter, target)

    result = ..some(.value = 42)
    replace_result($&result)
}

apply_edit := (.editor: &Virtual<Editor>, .target: $&Int32, .succeed: Bool) -> (.result: ?Int32) {
    result = edit(editor, target, succeed)
}

replace_result := (.target: $&?Int32) -> () { target&= ..none }

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    target :: Int32 = 41
    previous ::= &target
    editor ::= to_virtual<Editor>(&cell)
    result ::= apply_edit(&editor, $&target, false)

    match result {
        ..none { if previous&!= 41 { status_code = 1 } }
        ..some _ { status_code = 2 }
    }
}
