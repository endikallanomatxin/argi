..failure

run_main() -> !Void = ..ok Void() := {
    trace_buffer :: [4096]UInt8 = zeroed#(.t: [4096]UInt8)()
    tracer ::= FixedSizeErrorTracer(.buffer = view($&trace_buffer))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    result = ..error(.reason = ..failure)
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
