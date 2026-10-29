main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    bytes: [1]UInt8 = (0)
    fill_random_bytes(.self = system.rand_gen, .destination = view(.self = &bytes))
}
