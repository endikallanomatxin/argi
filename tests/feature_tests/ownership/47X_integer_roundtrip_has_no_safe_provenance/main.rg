main() -> (.status_code: Int32) := {
    value :: Int32 = 7
    address ::= cast#(.to: UIntNative)(.value = $&value)
    reference ::= cast#(.to: $&Int32)(.value = address)
    status_code = reference& - 7
}
