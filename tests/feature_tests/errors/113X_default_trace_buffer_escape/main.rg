escape := () -> (.tracer: FixedSizeErrorTracer) { tracer = FixedSizeErrorTracer() }

main := () -> () { tracer ::= escape() }
