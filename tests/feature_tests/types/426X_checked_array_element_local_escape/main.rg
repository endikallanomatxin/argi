first := (.array: &[2]Int32) -> (.result: &Int32) {
    result = &array&[0]
}
escape := () -> (.result: &Int32) {
    values :: [2]Int32 = (1, 2)
    result = first(.array = &values)
}
main := () -> () {
    escaped ::= escape()
    _ = escaped&
}
