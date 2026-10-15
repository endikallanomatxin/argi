_probe() -> (.status: CInt) : CFunction(.symbol = "argi_windows_clock_probe")
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi ::= system.ffi
    status_code = _probe().status
}
