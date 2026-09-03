main() -> (.status_code: Int32) := {
    borrowed ::= getenv(.name = "PATH")
    address ::= cast#(.to: UIntNative)(.value = borrowed)
    raw ::= raw_pointer#(.t: Char)(.address = address)
    safe ::= establish_fresh_reference#(.t: Char)(.raw = raw).reference
    byte ::= safe&
    status_code = 0
}
