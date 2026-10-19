main := () -> (.status_code: Int32) {
    numbers :: [2]Int32
    numbers[0] = 42
    complete ::= numbers
    status_code = complete[0]
}
