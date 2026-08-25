main(.system: System) -> (.status_code: Int32) := {
    byte :: UInt8 = 7
    address ::= cast#(.to: UIntNative)(.value = $&byte)
    raw ::= raw_pointer#(.t: UInt8)(.address = address)
    reference ::= establish_fresh_reference#(.t: UInt8)(.raw = raw)
    alias ::= reference

    end_root#(.t: UInt8)(.resource = ~reference)
    if alias& == 7 {
        status_code = 0
    }
}
