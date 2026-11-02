base: Int32 = 40
counter :: Int32 = base + 1

exercise := (.counter: $&Int32) -> (.result: Int32) {
    trace_buffer :: [4096]UInt8 = zeroed#(.t: [4096]UInt8)()
    tracer ::= FixedSizeErrorTracer(.buffer = view($&trace_buffer))
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    add_context(.context = "first context")
    add_context(.context = "ñ context")
    ErrorTracer#().reset_context(error_tracer)
    add_context(.context = "after reset")
    counter&= counter&+ 1
    result = counter&
}

calculate := () -> (.result: Int32) {
    local_counter :: Int32 = base + 1
    result = exercise(.counter = $&local_counter)
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run () -> (.value: Int32) { value = calculate() }
    if compiled != 42 { abort }
    #if calculate() == 42 {
        status_code = exercise(.counter = $&counter)
    } else {
        abort
    }
}
