python := import ("python")
numpy := import ("python/numpy")

run_main(.system: System) -> !Void = ..ok Void() := {
    interpreter ::= python.Python(.ffi = system.ffi)!
    input: [4]Float64 = (1.0, 2.0, 3.0, 4.0)
    other: [4]Float64 = (2.0, 3.0, 4.0, 5.0)
    left ::= numpy.Vector64(.interpreter = &interpreter, .values = view(.array = &input))!
    right ::= numpy.Vector64(.interpreter = &interpreter, .values = view(.array = &other))!
    squared ::= numpy.multiply(.left = &left, .right = &left)!
    added ::= numpy.add(.left = &left, .right = &right)!
    if numpy.length(.self = &left).count != 4 { abort }
    if numpy.dot(.left = &left, .right = &right)! != 40.0 { abort }
    if numpy.sum(.self = &squared)! != 30.0 { abort }
    output :: [5]Float64 = (0.0, 0.0, 0.0, 0.0, 99.0)
    if numpy.copy_values(.self = &added, .destination = view(.array = $&output))! != 4 { abort }
    if [
        output[0] != 3.0
        or output[1] != 5.0
        or output[2] != 7.0
        or output[3] != 9.0
        or output[4] != 99.0
    ] { abort }
    short: [1]Float64 = (1.0)
    smaller ::= numpy.Vector64(.interpreter = &interpreter, .values = view(.array = &short))!
    match numpy.add(.left = &left, .right = &smaller) { ..ok _ { abort } ..error _ {} }
    untouched :: [1]Float64 = (77.0)
    match numpy.copy_values(.self = &added, .destination = view(.array = $&untouched)) {
        ..ok _ { abort } ..error _ {}
    }
    if untouched[0] != 77.0 { abort }
    empty: [0]Float64 = ()
    zero ::= numpy.Vector64(.interpreter = &interpreter, .values = view(.array = &empty))!
    if numpy.sum(.self = &zero)! != 0.0 or numpy.dot(.left = &zero, .right = &zero)! != 0.0 {
        abort
    }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
