escaped := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
) {
    assume error_tracer

    args: [1]StringView = ("alpha",)
    source ::= CliArgumentViews(view(&args))
    erased ::= to_virtual#(ArgumentSource)(&source)
    result = get(&erased, 0)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    escaped()
}
