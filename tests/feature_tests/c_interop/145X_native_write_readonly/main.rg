native_write(.value: &Int32) -> (): CFunction(.symbol = "argi_access_write_one") where { writes(value) }
main := (.system: System) -> () {
    value :: Int32 = 7
    native_write(.value = &value, .ffi = system.ffi)
}
