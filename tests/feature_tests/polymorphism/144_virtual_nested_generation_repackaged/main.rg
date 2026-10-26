..failed

SimpleEditor<.Participant: Type>: Contract = (
    .edit : (.self: &Participant, .target: $&Int32, .mode: Int32) -> (.result: ?Int32) where {
        on result ..some { invalidates(target) }
        on result ..none {}
    }
)

Cell := (.unused: Int32)

implement SimpleEditor<Cell> (.edit = _impl_edit_Cell)

_impl_edit_Cell := (.self: &Cell, .target: $&Int32, .mode: Int32) -> (.result: ?Int32) {
    if mode == 1 {
        target&= 42
        result = ..some(.value = 42)
        return
    }
    result = ..none
}

apply_edit := (.editor: &Virtual<SimpleEditor>, .target: $&Int32, .mode: Int32) -> (
    .result: Errable<?Int32, (..failed)>
) {
    result = ..ok edit(editor, target, mode)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    target :: Int32 = 41
    previous ::= &target
    editor ::= to_virtual<SimpleEditor>(&cell)
    result ::= apply_edit(&editor, $&target, 0)

    match result {
        ..ok ~optional {
            match optional {
                ..none { if previous&!= 41 { status_code = 1 } }
                ..some _ { status_code = 2 }
            }
        }
        ..error _ { status_code = 3 }
    }

}
