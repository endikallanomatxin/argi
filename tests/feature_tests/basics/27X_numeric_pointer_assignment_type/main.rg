main() -> (.status_code: Int32 = 0) := {
    source :: UInt8 = 7
    destination :: UInt64 = 0
    pointer ::= $&destination
    pointer& = source
}
