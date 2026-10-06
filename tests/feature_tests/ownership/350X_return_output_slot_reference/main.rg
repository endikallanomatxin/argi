escape() -> (.owner: Int32, .reference: &Int32) := {
    owner = 7
    reference = &owner
}

main() -> () := {
    escaped ::= escape()
}
