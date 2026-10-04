python := import ("python")
numpy := import ("python/numpy")

main(.system: System) -> () := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi))
    values: [1]Float64 = (1.0)
    vector ::= unwrap_or_abort(
        .value = numpy.Vector64(.interpreter = &interpreter, .values = view(.array = &values))
    )
    python.deinit(.self = $&interpreter)
    numpy.sum(.self = &vector)
}
