deallocate(.data: $&UInt8, .ignored: Int32) -> () := {
}

main() -> (.status_code: Int32) := {
    byte :: UInt8 = 7
    owner ::= establish_fresh_reference#(.t: UInt8)(
        .raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte)),
    )
    alias ::= owner
    deallocate(.data = alias, .ignored = 0)
    if alias& == 7 {
        status_code = 0
    } else {
        status_code = 1
    }
    end_root#(.t: UInt8)(.resource = ~owner)
}
