First : CIncomplete
Second : CIncomplete
_create() -> (.result: RawPointer#(.t: First)) : CFunction
_read(.handle: RawPointer#(.t: Second)) -> (.result: CInt) : CFunction
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    result := _read(_create())
}
