Owned := (.value: Int32)

implement Deinit#(Owned) (
    .deinit = (.self: $&Owned) -> () {

    }
)

accept := #(.t: Type: ImplicitlyCopyable) (.value: &t, .flag: Bool = true) -> (.ok: Bool) {
    ok = flag
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    value :: Owned = (.value = 7)
    accept(.value = &value)
}
