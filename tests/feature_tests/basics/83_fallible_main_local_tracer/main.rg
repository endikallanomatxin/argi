..failure

main() -> !Void = ..ok Void() := {
    trace_buffer :: [4096]UInt8 = zeroed#(.t: [4096]UInt8)()
    tracer ::= FixedSizeErrorTracer(.buffer = view($&trace_buffer))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    result = ..error(.reason = ..failure)
}
