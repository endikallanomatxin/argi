..failed

Source#(.Participant: Type): Contract = (
    .get : (
        .self         : &Participant,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(?&Int32, (..failed))) where {
        on result ..ok {
            on result ..wrong { depends_on(result, self) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell := (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (
    .self         : &Cell,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(?&Int32, (..failed))) {
    assume error_tracer

    result = ..ok ..some(.value = &self&.value)
}

read_source := (
    .source       : &Virtual#(Source),
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(?&Int32, (..failed))) {
    assume error_tracer

    result = get(source)
}

main := () -> (.status_code: Int32 = 0) {
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
