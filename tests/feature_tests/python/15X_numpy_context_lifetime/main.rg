python := import ("python")
numpy := import ("python/numpy")

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi))
    values: [1]Float64 = (1.0)
    vector ::= unwrap_or_abort(
        .value = numpy.Vector64(.interpreter = &interpreter, .values = view(.self = &values))
    )
    Deinit#(python.Python).deinit(.self = $&interpreter)
    numpy.sum(.self = &vector)
}
