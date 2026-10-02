_first(.value: Int32) -> (.result: Int32) : CFunction(.symbol = "abs")
_second(.value: Float32) -> (.result: Float32) : CFunction(.symbol = "abs")
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi}
