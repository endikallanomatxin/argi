..startup_failed

fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Void {
    assume error_tracer

    result = ..error(.reason = ..startup_failed)
    add_context(.context = "starting application")
}

main := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> (.status_code: Int32 = 1) {
    assume error_tracer
    assume writer ::= $&system.terminal&.stderr
    fail()!!!
    status_code = 0
}
