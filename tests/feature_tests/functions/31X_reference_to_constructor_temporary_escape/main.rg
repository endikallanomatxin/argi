Box : Type = (.value: Int32)

bad() -> (.result: $&Box) := {
    result = $&Box(.value = 1)
}

main() -> (.status_code: Int32 = 0) := {
    box ::= bad().result
}
