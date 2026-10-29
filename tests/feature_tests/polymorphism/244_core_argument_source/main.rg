first := (
    .source       : &Virtual#(ArgumentSource),
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(StringView, (..out_of_bounds, ..invalid_utf8))) {
    assume error_tracer

    result = get(source, 0)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    args: [2]StringView = ("alpha", "beta")
    source ::= CliArgumentViews(view(&args))
    erased ::= to_virtual#(ArgumentSource)(&source)

    if length(&erased) != 2 { abort }
    if unwrap_or_abort(first(&erased)) != "alpha" { abort }
    if unwrap_or_abort(get(&erased, 1)) != "beta" { abort }

    match get(&erased, 2) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_bounds { abort } }
    }

    native ::= to_virtual#(ArgumentSource)(system.args)
    if length(&native) == 0 { abort }
    if byte_length(&unwrap_or_abort(get(&native, 0))).count == 0 { abort }
}
