main() -> (.status_code: Int32) := {
    raw ::= malloc(.size = 1)
    address ::= cast#(.to: UIntNative)(.value = raw)
    fabricated ::= cast#(.to: $&UInt8)(.value = address)
    fabricated& = 1
    status_code = 0
}
