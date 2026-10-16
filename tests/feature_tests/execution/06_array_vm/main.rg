change(.values: [2]Int32) -> (.result: [2]Int32) := {
    result = values
    result[0] = 20
}

main() -> (.status_code: Int32 = 0) := {
    original :: [2]Int32 = (1, 22)
    changed ::= change(.values = original)
    original[1] = 99
    index :: UIntNative = 0
    while index < 2 {
        status_code = status_code + changed[index]
        index = index + 1
    }
    nested: [2][2]Int32 = (
        (1, 2),
        (3, 4)
    )
    if nested[1][0] != 3 { abort }
    if original[0] != 1 or original[1] != 99 { abort }
}
