main(.system: System = System()) -> (.status_code: Int32) := {
    value :: Int32 = 7
    erased ::= cast#(.to: &Any)(.value = &value)
    if cast#(.to: UIntNative)(.value = erased) != cast#(.to: UIntNative)(.value = &value) {
        status_code = 1
        return
    }
    status_code = 0
}
