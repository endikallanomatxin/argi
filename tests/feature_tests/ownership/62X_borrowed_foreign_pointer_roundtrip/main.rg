main(.system: System) -> (.status_code: Int32) := {
    assume ffi := system.ffi
    borrowed ::= getenv(.name = "PATH")
    address ::= UIntNative(.value = borrowed)
    fabricated ::= cast#(.to: &Char)(.value = address)
    byte ::= fabricated&
    status_code = 0
}
