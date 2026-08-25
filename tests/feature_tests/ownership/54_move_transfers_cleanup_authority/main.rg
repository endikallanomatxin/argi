main() -> (.status_code: Int32) := {
    byte :: UInt8 = 7
    owner ::= establish_fresh_reference#(.t: UInt8)(
        .raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte)),
    )
    moved ::= ~owner
    end_root#(.t: UInt8)(.resource = ~moved)
    status_code = 0
}
