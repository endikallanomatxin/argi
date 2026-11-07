probe() -> (.result: CInt): CFunction(.symbol = "execution_protocol_probe") where { no_access() }
main := (.system: System) -> () {
    if probe(.ffi = system.ffi).result != 0 { abort }
}
