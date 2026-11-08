Box := (.value: &Int32)
select := #(.n: UIntNative) (.array: &Array#(.n = n, .t: Int32), .index: UIntNative) -> (.result: &Int32) {
    result = &array&[index]
}
escape := () -> (.result: Box) {
    values :: [2]Int32 = (1, 2)
    result = Box(select#(.n = 2)(.array = &values, .index = 1))
}
main := () -> () {
    escaped ::= escape()
    _ = escaped.value&
}
