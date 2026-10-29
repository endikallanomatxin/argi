escaped := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(StringView, (..out_of_bounds, ..invalid_utf8))) {
    assume error_tracer

    args: [1]StringView = ("alpha",)
    source ::= CliArgumentViews(view(&args))
    erased ::= to_virtual#(ArgumentSource)(&source)
    result = get(&erased, 0)
}

main := () -> () { escaped() }
