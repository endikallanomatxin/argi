..failure

check_fallible_result := (.error_tracer: $&Virtual<.contract: ErrorTracer> = reach error_tracer) -> !Void = ..ok Void(
) {
    result = ..error(.reason = ..failure)
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    trace_buffer :: [4096]UInt8 = zeroed<.t: [4096]UInt8>()
    tracer ::= FixedSizeErrorTracer(view($&trace_buffer))
    virtual_tracer ::= to_virtual<.contract: ErrorTracer>($&tracer)
    assume error_tracer ::= $&virtual_tracer

    check_fallible_result()!!!
    status_code = 0
}
