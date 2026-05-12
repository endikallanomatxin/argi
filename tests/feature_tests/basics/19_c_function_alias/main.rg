atoi(.string: &Char) -> (.value: Int32) : CFunction

main() -> (.status_code: Int32) := {
    parsed ::= atoi(.string = "42").value

    if parsed != 42 {
        status_code = 1
        return
    }

    status_code = 0
}
