..failed

Editor#(.Participant: Type): Contract = (
    .edit: (.self: &Participant, .target: $&Int32, .mode: Int32) -> (.result: Errable#(?Int32, (..failed))) where {
        on result ..ok {
            on result ..some { invalidates(target) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell: Type = (.unused: Int32)

implement Editor#(Cell) (.edit = _impl_edit_Cell)

_impl_edit_Cell := (.self: &Cell, .target: $&Int32, .mode: Int32) -> (.result: Errable#(?Int32, (..failed)))  {
    if mode == 2 {
        result = ..error(.reason = ..failed)
        return
    }
    if mode == 1 {
        target&= 42
        result = ..ok ..some(.value = 42)
        return
    }

    result = ..ok ..none
}

apply_edit(
        .editor : &Virtual#(Editor),
        .target : $&Int32,
        .mode   : Int32
    ) -> (
        .result : Errable#(?Int32, (..failed))
    ) := {
    pending ::= edit(editor, target, mode)
    copied ::= pending

    result = copied
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(0)
    target :: Int32 = 41
    previous ::= &target
    editor ::= to_virtual#(Editor)(&cell)
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
