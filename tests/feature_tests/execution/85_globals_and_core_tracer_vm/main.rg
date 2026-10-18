base: Int32 = 40
counter :: Int32 = base + 1

exercise := () -> (.result: Int32) {
    trace_buffer :: [4096]UInt8 = zeroed#(.t: [4096]UInt8)()
    tracer ::= FixedSizeErrorTracer(.buffer = view($&trace_buffer))
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    ErrorTracer#().reset_context(error_tracer)
    counter = counter + 1
    result = counter
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run exercise()
    if compiled != 42 { abort }
    #if exercise() == 42 {
        status_code = exercise()
    } else {
        abort
    }
}
