main() -> (.status_code: Int32 = 0) := {
    generator ::= Pcg32(.seed = 42)
    generator._state = 0
}
