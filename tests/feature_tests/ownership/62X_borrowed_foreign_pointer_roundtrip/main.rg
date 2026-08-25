main() -> (.status_code: Int32) := {
    borrowed ::= getenv(.name = "PATH")
    address ::= cast#(.to: UIntNative)(.value = borrowed)
    fabricated ::= cast#(.to: &Char)(.value = address)
    byte ::= fabricated&
    status_code = 0
}
