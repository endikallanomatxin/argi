main () -> (.status_code: Int32) := {
    value :: Int32 = 42
    ptr : &Int32 = &value

    addr :: UInt64 = cast#(.to: UInt64)(.value = ptr)
    ptr_roundtrip : &Int32 = cast#(.to: &Int32)(.value = addr)

    if ptr_roundtrip& != 42 {
        status_code = 1
        return
    }

    status_code = 0
}
