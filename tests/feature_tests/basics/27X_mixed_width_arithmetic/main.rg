main() -> (.status_code: Int32 = 0) := {
    wide :: UIntNative = 3
    narrow :: UInt8 = 2
    invalid ::= wide + narrow
}
