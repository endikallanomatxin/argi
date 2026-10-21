calculate(.value: Int32) -> (.result: Int32) := { result = value + 1 }

main() -> (.status_code: Int32) := {
    first ::= #run () -> (.result: Int32 = 20) {}
    second ::= #run () -> (.result: Int32) {
        local ::= #run () -> (.result: Int32 = 21) {}
        result = calculate(.value = local)
    }
    status_code = first + second
}
