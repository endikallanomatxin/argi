ForeignHandle: CIncomplete

..handle_creation_failed

OwnedHandle := (
    ._handle : RawPointer#(.t: ForeignHandle)
    ._ffi    : $&ForeignFunctionInterface
)

_create(.value: CInt, .fail: CBool) -> (.handle: RawPointer#(.t: ForeignHandle)): CFunction(
    .symbol = "argi_c_owned_create"
)

_destroy(.handle: RawPointer#(.t: ForeignHandle)) -> (): CFunction(
    .symbol = "argi_c_owned_destroy"
)

_read(.handle: RawPointer#(.t: ForeignHandle)) -> (.value: CInt): CFunction(
    .symbol = "argi_c_owned_read"
)

live() -> (.count: CInt): CFunction(.symbol = "argi_c_owned_live")

created() -> (.count: CInt): CFunction(.symbol = "argi_c_owned_created")

destroyed() -> (.count: CInt): CFunction(.symbol = "argi_c_owned_destroyed")

violations() -> (.count: CInt): CFunction(.symbol = "argi_c_owned_violations")

-- The C binding transfers one handle on success; a null result acquires
-- nothing. The wrapper keeps it private, provides no copy operation, and
-- retains the caller's capability for every access and release.
OwnedHandleInitArgs: Type = (
    .value : CInt,
    .fail  : Bool                       = false,
    .ffi   : $&ForeignFunctionInterface
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement Init#(OwnedHandle, OwnedHandleInitArgs) (
    .Result : Type = Errable#(.t: OwnedHandle, .reasons: (..handle_creation_failed))

    .init = OwnedHandleInitArgs -> (.result: Result) {
        assume error_tracer

        _init_value ::= ~value
        _init_fail ::= ~fail
        assume ffi := ~ffi

        constructed :: OwnedHandle

        handle := _create(.value = _init_value, .fail = _init_fail, .ffi = ffi)
        if handle.address == 0 {
            result = ..error(.reason = ..handle_creation_failed)
            return
        }
        constructed = (._handle = handle, ._ffi = ffi)
        result = ..ok ~constructed
    }
)

read := (.self: &OwnedHandle) -> (.value: CInt) {
    value = _read(.handle = self&._handle, .ffi = self&._ffi)
}

implement Deinit#(OwnedHandle) (
    .deinit = (.self: $&OwnedHandle) -> () {
        _destroy(.handle = self&._handle, .ffi = self&._ffi)
    }
)

GenericHandle := #(.t: Type) (
    ._handle : RawPointer#(.t: ForeignHandle)
    ._ffi    : $&ForeignFunctionInterface
    .tag     : t
)

GenericHandleInitArgs2: Type = #(.t: Type) (
    .tag : t,
    .ffi : $&ForeignFunctionInterface
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.t: Type) Init#(GenericHandle#(.t: t), GenericHandleInitArgs2#(t)) (
    .Result : Type = Errable#(.t: GenericHandle#(.t: t), .reasons: (..handle_creation_failed))

    .init = GenericHandleInitArgs2#(t) -> (.result: Result) {
        assume error_tracer

        _init_tag ::= ~tag
        assume ffi := ~ffi

        constructed :: GenericHandle#(.t: t)

        handle := _create(.value = 31, .fail = false, .ffi = ffi)
        if handle.address == 0 {
            result = ..error(.reason = ..handle_creation_failed)
            return
        }
        constructed = (._handle = handle, ._ffi = ffi, .tag = _init_tag)
        result = ..ok ~constructed
    }
)

implement#(.t: Type) Deinit#(GenericHandle#(.t: t)) (
    .deinit = (.self: $&GenericHandle#(.t: t)) -> () {
        _destroy(.handle = self&._handle, .ffi = self&._ffi)
    }
)
