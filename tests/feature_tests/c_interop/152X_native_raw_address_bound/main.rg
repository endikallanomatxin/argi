native_read(.value: RawPointer#(Int32)) -> (.result: Int32): CFunction(.symbol = "argi_access_read") where { reads(value) }
main := (.system: System) -> () {
    _ = native_read(.value = raw_pointer#(Int32)(.address = 0).raw, .ffi = system.ffi)
}
