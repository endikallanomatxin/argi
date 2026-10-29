Source := (.reference: &Int32)

implement Convert#(Source, &Int32) (
    .Result  : Type = &Int32
    .convert = (.value: Source, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Result) {
        result = value.reference
    }
)

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    integer :: Int32 = 7
    source ::= Source(&integer)
    borrowed ::= source | convert#(.to: &Int32)(_)
    if borrowed&!= 7 { status_code = 1 }
}
