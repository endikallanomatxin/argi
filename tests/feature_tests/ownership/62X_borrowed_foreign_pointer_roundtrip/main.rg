main := (.system: System) -> (.status_code: Int32) {
    assume ffi := system.ffi
    borrowed ::= getenv(.name = "PATH")
    address ::= borrowed | convert#(.to: UIntNative)(_)
    fabricated ::= cast#(.to: &CChar)(.value = address)
    byte ::= fabricated&
    status_code = 0
}
