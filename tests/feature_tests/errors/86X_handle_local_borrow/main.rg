..missing

attempt := (.value: &Int32, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: &Int32, .reasons: (..missing))
) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    source :: Int32 = 7
    pointer ::= attempt(.value = &source) handle error, value {
        local :: Int32 = 9
        value = &local
    }
    observed ::= pointer&
}
