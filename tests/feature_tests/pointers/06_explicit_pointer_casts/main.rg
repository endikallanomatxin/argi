main () -> (.status_code: Int32) := {
    value :: Int32 = 42
    ptr : &Int32 = &value

    addr :: UIntNative = cast#(.to: UIntNative)(.value = ptr)
    raw ::= raw_pointer#(.t: Int32)(.address = addr)
    ptr_roundtrip ::= establish_inherited_reference#(.t: Int32)(.raw = raw, .root = $&value)

    if ptr_roundtrip& != 42 {
        status_code = 1
        return
    }

    status_code = 0
}
