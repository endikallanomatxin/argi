..missing

fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Errable#(Int32, (..missing))) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

recover := (.initialize: Bool, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Int32) {
    assume error_tracer
    result = fail() handle error, value {
        if initialize { value = 7 }
    }
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    recover(false)
}
