main(.system: System) -> (.status_code: Int32) := {
    assume ffi := system.ffi
    borrowed ::= getenv(.name = "PATH")
    address ::= borrowed | convert#(.to: UIntNative)(_)
    raw ::= raw_pointer#(.t: Char)(.address = address)
    safe ::= establish_fresh_reference#(.t: Char)(.raw = raw).reference
    byte ::= safe&
    status_code = 0
}
