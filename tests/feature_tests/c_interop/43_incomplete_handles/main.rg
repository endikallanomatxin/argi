handles := import("./handles")
_create() -> (.result: RawPointer#(.t: handles.Handle)) : CFunction(.symbol = "argi_c_handle_create")
_read(.handle: RawPointer#(.t: handles.Handle)) -> (.result: CInt) : CFunction(.symbol = "argi_c_handle_read")
_probe() -> (.result: CInt) : CFunction(.symbol = "argi_c_handle_probe")
argi_c_handle_export(.handle: RawPointer#(.t: handles.Handle)) -> (.result: RawPointer#(.t: handles.Handle)) : CFunction(.export = true) := { result = handle }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    handle := _create()
    if handle.address == 0 or _read(handle) != 42 { status_code = 1 }
    if _probe() != 0 { status_code = 2 }
}
