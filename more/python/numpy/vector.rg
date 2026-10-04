python := import ("../")

..numpy_shape_mismatch

_PythonReasons: Type = (python ..python_error)

_NumpyReasons: Type = (python ..python_error, ..numpy_shape_mismatch)

-- Construction copies into Python-owned storage. The private object always
-- represents a one-dimensional native-endian Float64 array of this length.
Vector64: Type = (._object: python.Object, ._length: UIntNative)

Vector64 init(
        .interpreter : &python.Python,
        .values      : ArrayViewRO#(.t: Float64)
    ) -> (
        .result : Errable#(.t: Vector64, .reasons: _PythonReasons)
    ) := {
    object ::= python.numeric_array(.self = interpreter, .values = values)!
    result = ..ok(._object = ~object, ._length = length(.self = &values).count)
}

Vector64 deinit(.self: $&Vector64) -> () := { python.deinit(.self = $&self&._object) }

length(.self: &Vector64) -> (.count: UIntNative) := { count = self&._length }

add(
        .left  : &Vector64,
        .right : &Vector64
    ) -> (
        .result : Errable#(.t: Vector64, .reasons: _NumpyReasons)
    ) := {
    if left&._length != right&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }
    arguments: [1]&python.Object = (&right&._object)
    object ::= python.call_method(
        .self      = &left&._object
        .name      = "__add__"
        .arguments = view(.array = &arguments)
    )!
    result = ..ok(._object = ~object, ._length = left&._length)
}

multiply(
        .left  : &Vector64,
        .right : &Vector64
    ) -> (
        .result : Errable#(.t: Vector64, .reasons: _NumpyReasons)
    ) := {
    if left&._length != right&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }
    arguments: [1]&python.Object = (&right&._object)
    object ::= python.call_method(
        .self      = &left&._object
        .name      = "__mul__"
        .arguments = view(.array = &arguments)
    )!
    result = ..ok(._object = ~object, ._length = left&._length)
}

dot(
        .left  : &Vector64,
        .right : &Vector64
    ) -> (
        .result : Errable#(.t: Float64, .reasons: _NumpyReasons)
    ) := {
    if left&._length != right&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }
    arguments: [1]&python.Object = (&right&._object)
    object ::= python.call_method(
        .self      = &left&._object
        .name      = "dot"
        .arguments = view(.array = &arguments)
    )!
    value ::= python.to_float64(.self = &object)!
    result = ..ok value
}

sum(.self: &Vector64) -> (.result: Errable#(.t: Float64, .reasons: _NumpyReasons)) := {
    object ::= python.call_method(.self = &self&._object, .name = "sum")!
    value ::= python.to_float64(.self = &object)!
    result = ..ok value
}

copy_values(
        .self        : &Vector64,
        .destination : ArrayView#(.t: Float64)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: _NumpyReasons)
    ) := {
    if length(.self = &destination).count < self&._length {
        result = ..error(.reason = ..numpy_shape_mismatch)
        return
    }
    count ::= python.copy_numeric(.self = &self&._object, .destination = destination)!
    if count != self&._length { abort }
    result = ..ok count
}
