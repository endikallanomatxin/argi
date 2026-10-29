python := import ("../")

..numpy_shape_mismatch

_PythonReasons := (python ..python_error)

_NumpyReasons := (python ..python_error, ..numpy_shape_mismatch)

-- Construction copies into Python-owned storage. The private object always
-- represents a one-dimensional native-endian Float64 array of this length.
Vector64 := (._object: python.Object, ._length: UIntNative)

Vector64InitArgs: Type = (
    .interpreter  : &python.Python,
    .values       : ArrayView#(.t: Float64),
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement Init#(Vector64, Vector64InitArgs) (
    .Result : Type = Errable#(Vector64, _PythonReasons)

    .init = Vector64InitArgs -> (.result: Result) {
        assume error_tracer

        _init_interpreter ::= interpreter
        _init_values ::= values

        object ::= python.numeric_array(.self = _init_interpreter, .values = _init_values)!

        result = ..ok(._object = ~object, ._length = length(&_init_values).count)
    }
)

implement Deinit#(Vector64) (
    .deinit = (.self: $&Vector64) -> () {
        Deinit#(python.Object).deinit(.self = $&self&._object)
    }
)

length := (.self: &Vector64) -> (.count: UIntNative) { count = self&._length }

add := (.left: &Vector64, .right: &Vector64, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Vector64, _NumpyReasons)
) {
    assume error_tracer

    if left&._length != right&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }

    arguments: [1]&python.Object = (&right&._object)
    object ::= python.call_method(
        .self = &left&._object, .name = "__add__", .arguments = view(&arguments)
    )!

    result = ..ok(._object = ~object, ._length = left&._length)
}

multiply := (.left: &Vector64, .right: &Vector64, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Vector64, _NumpyReasons)
) {
    assume error_tracer

    if left&._length != right&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }

    arguments: [1]&python.Object = (&right&._object)
    object ::= python.call_method(
        .self = &left&._object, .name = "__mul__", .arguments = view(&arguments)
    )!

    result = ..ok(._object = ~object, ._length = left&._length)
}

dot := (.left: &Vector64, .right: &Vector64, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Float64, _NumpyReasons)
) {
    assume error_tracer

    if left&._length != right&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }

    arguments: [1]&python.Object = (&right&._object)
    object ::= python.call_method(
        .self = &left&._object, .name = "dot", .arguments = view(&arguments)
    )!
    value ::= python.to_float64(.self = &object)!

    result = ..ok value
}

sum := (.self: &Vector64, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Float64, _NumpyReasons)
) {
    assume error_tracer

    object ::= python.call_method(.self = &self&._object, .name = "sum")!
    value ::= python.to_float64(.self = &object)!

    result = ..ok value
}

copy_values := (
    .self         : &Vector64,
    .destination  : MutableArrayView#(.t: Float64),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(UIntNative, _NumpyReasons)) {
    assume error_tracer

    if length(&destination).count < self&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }

    count ::= python.copy_numeric(.self = &self&._object, .destination = destination)!

    if count != self&._length { abort }

    result = ..ok count
}
