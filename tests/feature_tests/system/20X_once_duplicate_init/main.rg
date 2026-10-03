Token : Type = ()

once Token init() -> (.result: Token) := {
    result = ()

}

main() -> (.status_code: Int32) := {
    first := Token()
    second := Token()
    status_code = 0
}
