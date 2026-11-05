native_write(.value: $&Any) -> (): CFunction(.symbol = "argi_access_write") where { writes(value) }
main := (.system: System) -> () {
    value :: Int32 = 7
    erased ::= trusted_mutable_reinterpret_reference#(.from: Int32, .to: Any)(.base = $&value).reference
    native_write(.value = erased, .ffi = system.ffi)
}
