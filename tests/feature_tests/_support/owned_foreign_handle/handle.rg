ForeignHandle : CIncomplete
..handle_creation_failed

OwnedHandle : Type = (
    ._handle: RawPointer#(.t: ForeignHandle)
    ._ffi: $&ForeignFunctionInterface
)

_create(.value: CInt, .fail: CBool) -> (.handle: RawPointer#(.t: ForeignHandle)) : CFunction(.symbol = "argi_c_owned_create")
_destroy(.handle: RawPointer#(.t: ForeignHandle)) -> () : CFunction(.symbol = "argi_c_owned_destroy")
_read(.handle: RawPointer#(.t: ForeignHandle)) -> (.value: CInt) : CFunction(.symbol = "argi_c_owned_read")
live() -> (.count: CInt) : CFunction(.symbol = "argi_c_owned_live")
created() -> (.count: CInt) : CFunction(.symbol = "argi_c_owned_created")
destroyed() -> (.count: CInt) : CFunction(.symbol = "argi_c_owned_destroyed")
violations() -> (.count: CInt) : CFunction(.symbol = "argi_c_owned_violations")

-- The C binding transfers one handle on success; a null result acquires
-- nothing. The wrapper keeps it private, provides no copy operation, and
-- retains the caller's capability for every access and release.
init(.p: $&OwnedHandle, .value: CInt, .fail: Bool = false, .ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Errable#(.t: Void, .reasons: (..handle_creation_failed))) := {
    handle := _create(.value = value, .fail = fail, .ffi = ffi)
    if handle.address == 0 {
        result = ..error(.reason = ..handle_creation_failed)
        return
    }
    p& = (._handle = handle, ._ffi = ffi)
    result = ..ok Void()
}

read(.self: &OwnedHandle) -> (.value: CInt) := {
    value = _read(.handle = self&._handle, .ffi = self&._ffi)
}

deinit(.self: $&OwnedHandle) -> () := {
    _destroy(.handle = self&._handle, .ffi = self&._ffi)
}

GenericHandle#(.t: Type) : Type = (
    ._handle: RawPointer#(.t: ForeignHandle)
    ._ffi: $&ForeignFunctionInterface
    .tag: t
)

init#(.t: Type)(.p: $&GenericHandle#(.t: t), .tag: t, .ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Errable#(.t: Void, .reasons: (..handle_creation_failed))) := {
    handle := _create(.value = 31, .fail = false, .ffi = ffi)
    if handle.address == 0 {
        result = ..error(.reason = ..handle_creation_failed)
        return
    }
    p& = (._handle = handle, ._ffi = ffi, .tag = tag)
    result = ..ok Void()
}

deinit#(.t: Type)(.self: $&GenericHandle#(.t: t)) -> () := {
    _destroy(.handle = self&._handle, .ffi = self&._ffi)
}
