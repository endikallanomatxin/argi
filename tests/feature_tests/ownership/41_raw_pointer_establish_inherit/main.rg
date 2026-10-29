main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    value :: Int32 = 9
    address ::= $&value | convert#(.to: UIntNative)(_)
    raw ::= raw_pointer#(.t: Int32)(.address = address)
    reference ::= trusted_establish_inherited_reference#(.t: Int32)(.raw = raw, .root = $&value)
    status_code = reference&- 9
}
