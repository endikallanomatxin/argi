escape() -> (.result: ErrorTrace) := {
    tracer ::= NoopErrorTracer()
    virtual_tracer ::= to_virtual#(ErrorTracer)($&tracer)
    result = ErrorTrace($&virtual_tracer)
}

main() -> () := {
    escaped ::= escape()
}
