main(.system: System = System()) -> (.status_code: Int32) := {
    address :: UIntNative = 1
    erased ::= cast#(.to: &Any)(.value = address)
    typed ::= cast#(.to: &Int32)(.value = erased)
    status_code = typed&
}
