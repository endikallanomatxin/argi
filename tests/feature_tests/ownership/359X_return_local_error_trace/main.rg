escape() -> (.result: $&Virtual#(.contract: ErrorTracer)) := {
    tracer ::= NoopErrorTracer()
    virtual_tracer ::= to_virtual#(ErrorTracer)($&tracer)
    result = $&virtual_tracer
}

main() -> () := {
    escaped ::= escape()
}
