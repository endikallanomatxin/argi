argi_c_scale(.value: Int32, .factor: Float32) -> (.result: Float32) : CFunction

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    factor :: Float32 = 2.0
    result := argi_c_scale(7, factor)
    expected :: Float32 = 14.0
    if result != expected { status_code = 1 }
}
