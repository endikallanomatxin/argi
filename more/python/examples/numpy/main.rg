python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    input: [4]Float64 = (1.0, 2.0, 3.0, 4.0)
    array ::= unwrap_or_abort(.value = python.numeric_array(.self = &interpreter,
            .values = view(.array = &input))).result
    arguments: [1]&python.Object = (&array)
    squared ::= unwrap_or_abort(.value = python.call_method(.self = &array, .name = "__mul__",
            .arguments = view(.array = &arguments))).result
    output :: [4]Float64 = (0.0, 0.0, 0.0, 0.0)
    destination: ArrayView#(.t: Float64) = view(.array = $&output)
    if unwrap_or_abort(.value = python.copy_numeric(.self = &squared,
            .destination = destination)).result != 4 { abort }
    expected: [4]Float64 = (1.0, 4.0, 9.0, 16.0)
    index :: UIntNative = 0
    while index < 4 {
        if output[index] != expected[index] { abort }
        index = index + 1
    }
    shape: [2]Int32 = (2, 2)
    reshape_arguments ::= unwrap_or_abort(.value = python.positional_arguments(.self = &interpreter,
            .values = view(.array = &shape))).result
    matrix ::= unwrap_or_abort(.value = python.call_method(.self = &array, .name = "reshape",
            .arguments = &reshape_arguments)).result
    match python.copy_numeric(.self = &matrix, .destination = destination) {
        ..error _ {} ..ok _ { abort }
    }
    index = 0
    while index < 4 {
        if output[index] != expected[index] { abort }
        index = index + 1
    }
}
