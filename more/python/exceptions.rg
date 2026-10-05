-- These owners retain immutable native text, not Python objects. A captured
-- exception can survive later errors and interpreter finalization; only its
-- ordinary FFI capability must remain alive.
Exception: Type = (._handle: UIntNative, ._ffi: $&ForeignFunctionInterface)

Outcome#(.t: Type): Type = (..ok t, ..error Exception)

_error_snapshot(.context: UIntNative) -> (.handle: UIntNative): CFunction(
    .symbol = "_argi_python_error_snapshot"
)

_initialization_snapshot() -> (.handle: UIntNative): CFunction(
    .symbol = "_argi_python_initialization_snapshot"
)

_exception_clone(.handle: UIntNative) -> (.handle: UIntNative): CFunction(
    .symbol = "_argi_python_exception_clone"
)

_exception_release(.handle: UIntNative) -> (): CFunction(
    .symbol = "_argi_python_exception_release"
)

_exception_size(.handle: UIntNative, .part: Int32) -> (.length: UIntNative): CFunction(
    .symbol = "_argi_python_exception_size"
)

_exception_copy(
        .handle      : UIntNative,
        .part        : Int32,
        .destination : RawPointer#(.t: UInt8),
        .length      : UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_exception_copy")

Exception deinit(.self: $&Exception) -> () := {
    assume ffi := self&._ffi
    _exception_release(.handle = self&._handle)
}

snapshot_error(.self: &Python) -> (.exception: Exception) := {
    assume ffi := self&._ffi
    exception = (._handle = _error_snapshot(.context = self&._handle).handle, ._ffi = self&._ffi)
}

initialization_error(.ffi: $&ForeignFunctionInterface) -> (.exception: Exception) := {
    assume ffi
    exception = (._handle = _initialization_snapshot().handle, ._ffi = ffi)
}

clone(.self: &Exception) -> (.exception: Exception) := {
    assume ffi := self&._ffi
    exception = (._handle = _exception_clone(.handle = self&._handle).handle, ._ffi = self&._ffi)
}

-- Convert an operation's ordinary Errable immediately, before executing another
-- Python operation. Its error branch then owns the exact captured failure.
capture#(
        .t : Type
    )(
        .self  : &Python,
        .value : Errable#(.t: t, .reasons: (..python_error))
    ) -> (
        .result : Outcome#(.t: t)
    ) := {
    match value {
        ..ok ~payload { result = ..ok ~payload }
        ..error _ { result = ..error snapshot_error(.self = self).exception }
    }
}

_exception_text(
        .self      : &Exception,
        .part      : Int32,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t : String,

            .reasons : (..out_of_memory)
        )
    ) := {
    assume ffi := self&._ffi
    count ::= _exception_size(.handle = self&._handle, .part = part).length
    text ::= string_with_length(.allocator = allocator, .length = count)!

    if [
        _exception_copy(
            .handle      = self&._handle
            .part        = part
            .destination = text.allocation.data
            .length      = count
        ).status
        != 0
    ] { abort }

    result = ..ok ~text
}

exception_type(
        .self      : &Exception,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..out_of_memory)
        )
    ) := {
    result = _exception_text(.self = self, .part = 0, .allocator = allocator)
}

exception_message(
        .self      : &Exception,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..out_of_memory)
        )
    ) := {
    result = _exception_text(.self = self, .part = 1, .allocator = allocator)
}

exception_traceback(
        .self      : &Exception,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..out_of_memory)
        )
    ) := {
    result = _exception_text(.self = self, .part = 2, .allocator = allocator)
}
