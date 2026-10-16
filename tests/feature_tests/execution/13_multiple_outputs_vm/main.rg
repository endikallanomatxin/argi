split_number(.value: Int32) -> (.quotient: Int32, .remainder: Int32) := {
    quotient = value / 10
    remainder = value % 10
}

inspect(.value: &Int32) -> (.reference: &Int32, .present: Bool = true) := {
    reference = value
}

main() -> (.status_code: Int32 = 0) := {
    result ::= split_number(.value = 402)
    total :: Int32 = result.quotient + result.remainder
    borrowed ::= inspect(.value = &total)
    if borrowed.present { status_code = borrowed.reference&}
    split_number(.value = 17)
}
