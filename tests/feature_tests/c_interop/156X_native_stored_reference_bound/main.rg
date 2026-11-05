Context := (.value: &Int32)
native_read(.context: &Context) -> (.result: Int32): CFunction(.symbol = "argi_access_read") where { reads(context) reads(context.value) }
main := (.system: System) -> () {
    value :: Int32 = 7
    context: Context = (.value = &value)
    _ = native_read(.context = &context, .ffi = system.ffi)
}
