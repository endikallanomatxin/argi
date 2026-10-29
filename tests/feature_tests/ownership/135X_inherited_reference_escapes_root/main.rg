escape := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.reference: $&Int32) {
    assume error_tracer
    value :: Int32 = 7
    raw ::= raw_pointer#(.t: Int32)(.address = $&value | convert#(.to: UIntNative)(_)).raw
    reference = trusted_establish_inherited_reference#(.t: Int32)(
        .raw = raw, .root = erase_mutable_reference#(.t: Int32)(.base = $&value).reference
    ).reference
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    escaped ::= escape()
    status_code = escaped&
}
