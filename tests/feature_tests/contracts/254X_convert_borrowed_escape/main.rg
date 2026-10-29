Source := (.reference: &Int32)

implement Convert#(Source, &Int32) (
    .Result  : Type = &Int32
    .convert = (.value: Source, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Result) {
        result = value.reference
    }
)

make := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: &Int32) {
    assume error_tracer
    integer :: Int32 = 7
    result = Source(&integer) | convert#(.to: &Int32)(_)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    escaped ::= make()
}
