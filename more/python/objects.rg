_set_attribute(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .bytes   : &UInt8,
        .length  : UIntNative,
        .value   : RawPointer#(.t: _PyObject)
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_set_attribute")

_iterator(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject)
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_iterator")

_next(
        .context   : UIntNative,
        .object    : RawPointer#(.t: _PyObject),
        .exhausted : $&Int32
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_next")

call_method(
        .self      : &Object,
        .name      : StringView,
        .arguments : ArrayViewRO#(.t: &Object) = _no_arguments(),
        .keywords  : ?&Object                  = _no_keywords()
    ) -> (
        .result : Errable#(
            .t : Object,

            .reasons : (..python_error)
        )
    ) := {
    method ::= attribute(.self = self, .name = name)!

    result = call(.self = &method, .arguments = arguments, .keywords = keywords)
}

call_method(
        .self      : &Object,
        .name      : StringView,
        .arguments : &Object,
        .keywords  : ?&Object    = _no_keywords()
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    method ::= attribute(.self = self, .name = name)!

    result = call(.self = &method, .arguments = arguments, .keywords = keywords)
}

set_attribute(
        .self  : &Object,
        .name  : StringView,
        .value : &Object
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._python&._ffi

    if [
        _set_attribute(
            .context = self&._python&._handle
            .object  = self&._handle
            .bytes   = name.data

            .length = name.length
            .value  = value&._handle
        ).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }

    result = ..ok Void()
}

tuple(
        .self   : &Python,
        .values : ArrayViewRO#(.t: &Object) = _no_arguments()
    ) -> (
        .result : Errable#(
            .t : Object,

            .reasons : (..python_error)
        )
    ) := {
    result = positional_arguments(.self = self, .values = values)
}

-- Python's next protocol is fallible. Exhaustion is a successful absent value,
-- so this iterator deliberately uses an explicit next call instead of promising
-- the core Iterator abstract's infallible next/has_next protocol.
PythonIterator: Type = (._object: Object)

iterate(.self: &Object) -> (.result: Errable#(.t: PythonIterator, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    object ::= _owned(
        .self   = self&._python
        .handle = _iterator(.context = self&._python&._handle, .object = self&._handle).handle
    )!

    result = ..ok(._object = ~object)
}

next(.self: $&PythonIterator) -> (.result: Errable#(.t: ?Object, .reasons: (..python_error))) := {
    assume ffi := self&._object._python&._ffi
    exhausted :: Int32 = 0
    handle ::= _next(
        .context   = self&._object._python&._handle
        .object    = self&._object._handle
        .exhausted = $&exhausted
    ).handle

    if exhausted == 1 {
        result = ..ok ..none
        return
    }

    if handle.address == 0 {
        result = ..error(.reason = ..python_error)
        return
    }

    result = ..ok ..some(.value = (._handle = handle, ._python = self&._object._python))
}
