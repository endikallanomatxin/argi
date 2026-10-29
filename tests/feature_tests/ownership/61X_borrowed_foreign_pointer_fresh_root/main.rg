main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    borrowed ::= getenv(.name = "PATH")
    address ::= borrowed | convert#(.to: UIntNative)(_)
    raw ::= raw_pointer#(.t: CChar)(.address = address)
    safe ::= establish_fresh_reference#(.t: CChar)(.raw = raw).reference
    byte ::= safe&
    status_code = 0
}
