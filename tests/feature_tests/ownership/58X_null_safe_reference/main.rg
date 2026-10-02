main() -> (.status_code: Int32) := {
    zero :: UIntNative = 0
    reference ::= cast#(.to: $&Int32)(.value = zero)
    status_code = reference&
}
