main() -> (.status_code: Int32) #raw_boundary := {
    value :: Int32 = 7
    address ::= cast#(.to: UIntNative)(.value = $&value)
    raw ::= raw_pointer#(.t: Int32)(.address = address)
    reference ::= establish_fresh_reference#(.t: Int32)(.raw = raw)
    status_code = reference& - 7
}
