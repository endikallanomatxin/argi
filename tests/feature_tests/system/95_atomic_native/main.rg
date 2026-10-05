probe() -> (.status: Int32): CFunction(.symbol = "argi_atomic_probe")

main(.system: System) -> (.status_code: Int32 = 0) := {
    status_code = probe(.ffi = system.ffi).status
}
