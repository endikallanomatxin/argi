_probe() -> (.status: Int32): CFunction(.symbol = "argi_windows_process_quote_probe")
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi ::= system.ffi
    if _probe().status != 0 { abort }
}
