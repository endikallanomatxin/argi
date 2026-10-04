identity(.value: Int32) -> (.result: Int32) := { result = value }
main() -> (.status_code: Int32 = 0) := {
    result ::= 1 | identity(.value = 2 | identity(.value = _))
}
