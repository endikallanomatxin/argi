run_main() -> !Void = ..ok Void() := {
    scalar ::= UnicodeScalar(.value = 65)!
    scalar._value = 55296
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
