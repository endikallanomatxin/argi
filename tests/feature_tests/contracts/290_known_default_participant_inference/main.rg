calls :: Int32 = 0

make_default := () -> (.value: Int32) {
    calls = calls + 1
    value = 7
}

identity := <.T: Type> (.value: T = make_default()) -> (.result: T) {
    result = value
}

main := () -> (.status_code: Int32 = 0) {
    if calls != 0 { status_code = 1 }
    supplied ::= identity(.value = 42)
    if supplied != 42 or calls != 0 { status_code = 2 }
    first ::= identity()
    second ::= identity()
    if first != 7 or second != 7 or calls != 2 { status_code = 3 }
}
