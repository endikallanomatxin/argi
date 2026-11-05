Box := (.reference: $&Int32)
native_write(.box: $&Box) -> (): CFunction(.symbol = "argi_access_write") where { writes(box) }
main := (.system: System) -> () {
    value :: Int32 = 7
    box: Box = (.reference = $&value)
    native_write(.box = $&box, .ffi = system.ffi)
}
