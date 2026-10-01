main() -> (.status_code: Int32 = 0) := {
    source :: UInt8 = 7
    destination :: UInt8 = source
    destination = 8
    pointer ::= $&destination
    pointer& = 9
    if destination != 9 { status_code = 1 }
}
