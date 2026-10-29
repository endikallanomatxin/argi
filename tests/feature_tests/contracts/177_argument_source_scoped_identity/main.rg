read_first := #(.T: Type: ArgumentSource#(T)) (
    .source: &T, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.text: StringView) {
    assume error_tracer
    if ArgumentSource#().length(source).count != 2 { abort }
    text = unwrap_or_abort(.value = ArgumentSource#().get(source, .index = 0))
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    values: [2]StringView = ("first", "second")
    source ::= CliArgumentViews(view(&values))
    if read_first(&source).text != "first" { abort }
    erased ::= to_virtual#(.contract: ArgumentSource)(.value = &source)
    if read_first(&erased).text != "first" { abort }
}
