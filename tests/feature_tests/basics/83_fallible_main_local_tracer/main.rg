..failure

run_main(.error_tracer: $&Virtual#(.abstract: ErrorTracer) = reach error_tracer) -> !Void = ..ok Void() := {
    result = ..error(.reason = ..failure)
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    trace_buffer :: [4096]UInt8 = zeroed#(.t: [4096]UInt8)()
    tracer ::= FixedSizeErrorTracer(view($&trace_buffer))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)($&tracer)
    assume error_tracer ::= $&virtual_tracer

    run_main()!!!
    status_code = 0
}
