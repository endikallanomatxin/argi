main() -> (.status_code: Int32) #raw_boundary := {
    value :: Int32 = 9
    address ::= cast#(.to: UIntNative)(.value = $&value)
    raw ::= raw_pointer#(.t: Int32)(.address = address)
    reference ::= establish_inherited_reference#(.t: Int32)(.raw = raw, .root = $&value)
    status_code = reference& - 9
}
