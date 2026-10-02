_static() -> (.pointer: RawPointer#(.t: UInt8)) : CFunction(.symbol = "argi_c_static")
_read(.pointer: RawPointer#(.t: UInt8)) -> (.value: Int32) : CFunction(.symbol = "argi_c_read")
_echo(.pointer: RawPointer#(.t: UInt8)) -> (.result: RawPointer#(.t: UInt8)) : CFunction(.symbol = "argi_c_echo")
_probe() -> (.status: Int32) : CFunction(.symbol = "argi_c_pointer_probe")
_forward() -> (.pointer: RawPointer#(.t: UInt8)) := { pointer = _static() }
_identity(.pointer: RawPointer#(.t: UInt8)) -> (.result: RawPointer#(.t: UInt8)) : CFunction := { result = pointer }
argi_pointer_export(.pointer: RawPointer#(.t: UInt8)) -> (.result: RawPointer#(.t: UInt8)) : CFunction(.export = true) := { result = pointer }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    pointer := _forward()
    if pointer.address == 0 { status_code = 1 }
    if _read(pointer) != 42 { status_code = 2 }
    echoed := _echo(pointer)
    if echoed.address != pointer.address { status_code = 3 }
    identity := _identity(pointer)
    if identity.address != pointer.address { status_code = 4 }
    null := raw_pointer#(.t: UInt8)(.address = 0)
    if _read(null) != 0 { status_code = 5 }
    if _probe() != 0 { status_code = 6 }
}
