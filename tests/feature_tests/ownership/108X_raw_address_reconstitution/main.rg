forge() -> (.pointer: &UInt8) := {
    address :: UIntNative = 4096
    pointer = cast#(.to: &UInt8)(.value = address)
}

main() -> (.status_code: Int32) := {
    pointer ::= forge()
    status_code = 0
}
