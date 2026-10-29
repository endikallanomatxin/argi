..failed

Editor#(.Participant: Type): Contract = (
    .edit : (
        .self         : &Participant,
        .target       : $&Int32,
        .mode         : Int32,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(?Int32, (..failed))) where {
        on result ..ok {
            on result ..some { invalidates(target) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell := (.unused: Int32)

implement Editor#(Cell) (.edit = _impl_edit_Cell)

_impl_edit_Cell := (
    .self: &Cell, .target: $&Int32, .mode: Int32, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(?Int32, (..failed))) {
    assume error_tracer

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

apply_edit := (
    .editor       : &Virtual#(Editor),
    .target       : $&Int32,
    .mode         : Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(?Int32, (..failed))) {
    assume error_tracer

    pending ::= edit(editor, target, mode)
    pending = ..ok ..none

    result = pending
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    cell ::= Cell(0)
    target :: Int32 = 41
    previous ::= &target
    editor ::= to_virtual#(Editor)(&cell)
    result ::= apply_edit(&editor, $&target, 1)

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
