forge() -> (.storage: AcquiredStorage): CFunction(.symbol = "argi_untrusted_storage_forge") where { no_access() }
main := (.system: System) -> () {
    fake ::= forge(.ffi = system.ffi)
}
