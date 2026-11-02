Editor#(.Participant: Type): Contract = (
    .edit : (
        .self         : &Participant,
        .target       : $&Int32,
        .other        : $&Int32,
        .change       : Bool,
        .change_other : Bool
    ) -> (.auxiliary: ?Int32, .result: ?Int32) where {
        on auxiliary ..some { invalidates(other) }
        on auxiliary ..none {}
        on result ..some { invalidates(target) }
        on result ..none {}
    }
)

Cell := (.unused: Int32)

implement Editor#(Cell) (.edit = _impl_edit_Cell)

_impl_edit_Cell := (
    .self: &Cell, .target: $&Int32, .other: $&Int32, .change: Bool, .change_other: Bool
) -> (.auxiliary: ?Int32, .result: ?Int32) {
    if change_other {
        other&= 55
        auxiliary = ..some(.value = 55)
    } else {
        auxiliary = ..none
    }

    if change {
        target&= 42
        result = ..some(.value = 42)
    } else {
        result = ..none
    }
}

forward := (.editor: &Virtual#(Editor), .target: $&Int32, .other: $&Int32) -> (.result: ?Int32) {
    returned ::= edit(editor, target, other, false, true)
    target&= 56
    result = returned.result
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    editor ::= to_virtual#(Editor)(&cell)
    target :: Int32 = 41
    other :: Int32 = 54
    previous ::= &target
    outcome ::= forward(&editor, $&target, $&other)

    match outcome {
        ..none { if previous&!= 56 or target != 56 { status_code = 1 } }
        ..some _ { status_code = 2 }
    }
}
