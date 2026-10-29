main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    value :: Int32 = 7
    address ::= $&value | convert#(.to: UIntNative)(_)
    raw ::= raw_pointer#(.t: Int32)(.address = address)
    reference ::= establish_fresh_reference#(.t: Int32)(.raw = raw)
    status_code = reference&- 7
}
