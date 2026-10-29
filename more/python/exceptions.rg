-- These owners retain immutable native text, not Python objects. A captured
-- exception can survive later errors and interpreter finalization; only its
-- ordinary FFI capability must remain alive.
Exception := (._handle: UIntNative, ._ffi: $&ForeignFunctionInterface)

Outcome := #(.t: Type) (..ok t, ..error Exception)

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
    .handle: UIntNative, .part: Int32, .destination: RawPointer#(.t: UInt8), .length: UIntNative
) -> (.status: Int32): CFunction(.symbol = "_argi_python_exception_copy")

implement Deinit#(Exception) (
    .deinit = (.self: $&Exception) -> () {
        assume ffi := self&._ffi
        _exception_release(.handle = self&._handle)
    }
)

snapshot_error := (.self: &Python) -> (.exception: Exception) {
    assume ffi := self&._ffi
    exception = (
        ._handle = _error_snapshot(.context = self&._handle).handle
        ._ffi    = self&._ffi
    )
}

initialization_error := (.ffi: $&ForeignFunctionInterface) -> (.exception: Exception) {
    assume ffi
    exception = (._handle = _initialization_snapshot().handle, ._ffi = ffi)
}

_python_exception_clone := (.self: &Exception, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Exception
) {
    assume ffi := self&._ffi
    result = (._handle = _exception_clone(.handle = self&._handle).handle, ._ffi = self&._ffi)
}

-- Convert an operation's ordinary Errable immediately, before executing another
-- Python operation. Its error branch then owns the exact captured failure.
capture := #(.t: Type) (.self: &Python, .value: Errable#(t, (..python_error))) -> (
    .result : Outcome#(.t: t)
) {
    match value {
        ..ok ~payload { result = ..ok ~payload }
        ..error _ { result = ..error snapshot_error(.self = self).exception }
    }
}

_exception_text := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .self         : &Exception,
    .part         : Int32,
    .allocator    : $&AllocatorType,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(String, (..out_of_memory))) {
    assume error_tracer

    assume ffi := self&._ffi
    count ::= _exception_size(.handle = self&._handle, .part = part).length
    text ::= _native_byte_buffer(.allocator = allocator, .count = count)!
    storage ::= view($&text)

    if [
        _exception_copy(
            .handle      = self&._handle
            .part        = part
            .destination = _native_buffer_address(.bytes = storage).address
            .length      = count
        ).status
        != 0
    ] { abort }

    result = _native_text(.bytes = view(&text), .allocator = allocator)
}

exception_type := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .self: &Exception, .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(String, (..out_of_memory))) {
    assume error_tracer

    result = _exception_text(.self = self, .part = 0, .allocator = allocator)
}

exception_message := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .self: &Exception, .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(String, (..out_of_memory))) {
    assume error_tracer

    result = _exception_text(.self = self, .part = 1, .allocator = allocator)
}

exception_traceback := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .self: &Exception, .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(String, (..out_of_memory))) {
    assume error_tracer

    result = _exception_text(.self = self, .part = 2, .allocator = allocator)
}
