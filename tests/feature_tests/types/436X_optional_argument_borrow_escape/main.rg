ap := import ("command_line_interface/argument_parsing")

Args := (.output: ap.Option#(?StringView))

escape := (.allocator: Virtual#(Allocator), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Args, ap.TypedReasons, ErrorWithTrace#(ap.TypedReasons))
) {
    values: [1]StringView = ("--output=app")
    source ::= ap.ArgumentViews(view(&values))
    result = ap.parse#(Args)(
        .source = &source, .allocator = allocator, .error_tracer = error_tracer
    )
}

main := (.system: System) -> () {
    escape(.allocator = system.page_allocator, .error_tracer = $&noop_error_tracer)
}
