..failed

Source#(.Participant: Type): Contract = (
    .get : (
        .self         : &Participant,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(Int32, (..failed))) where {
        on result ..ok {}
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
) -> (.result: Errable#(Int32, (..failed))) {
    assume error_tracer

    if self&.value == 0 {
        result = ..error(.reason = ..failed)
    } else {
        result = ..ok self&.value
    }
}

read_source := (
    .source       : &Virtual#(Source),
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Int32, (..failed))) {
    assume error_tracer

    result = get(source)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)
    match read_source(&source) {
        ..ok value { if value != 42 { status_code = 1 } }
        ..error _ { status_code = 1 }
    }
}
