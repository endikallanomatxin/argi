main() -> (.status_code: Int32) := {
    address :: UIntNative = 1
    pointer : &UInt8 = cast#(.to: &UInt8)(.value = address)
    value ::= pointer&
    status_code = 0
}
