Token : Type = ()

once init(.p: $&Token) -> () := {
}

main() -> (.status_code: Int32) := {
    first := Token()
    second := Token()
    status_code = 0
}
