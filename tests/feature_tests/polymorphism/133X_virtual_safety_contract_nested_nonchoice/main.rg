..failed

Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(Int32, (..failed))
    ) where {
        on result ..ok {
            on result ..some { depends_on(result, self) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell := (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Int32, (..failed))
) {
    assume error_tracer

    result = ..ok 42
}

read_source := (.source: &Virtual#(Source), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Int32, (..failed))
) {
    assume error_tracer

    result = get(source)
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)

    match read_source(&source) {
        ..ok ~optional {
            match optional {
                ..some reference { if reference.value&!= 42 { status_code = 1 } }
                ..none { status_code = 2 }
            }
        }
        ..error _ { status_code = 3 }
    }
}
