Pair: CStruct = (.first: Int32, .second: Int32)
native_read(.pair: &Pair) -> (.value: Int32): CFunction(.symbol = "argi_access_read") where { reads(pair.missing) }
main := (.system: System) -> () {
    pair: Pair = (.first = 1, .second = 2)
    _ = native_read(.pair = &pair, .ffi = system.ffi)
}
