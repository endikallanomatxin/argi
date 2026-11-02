change := (.values: [2]Int32) -> (.result: [2]Int32) {
    result = values
    result[0] = 20
}

forward_references := (.values: [2]&Int32) -> (.result: [2]&Int32) {
    result = values
}

main := () -> (.status_code: Int32 = 0) {
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
    first :: Int32 = 40
    second :: Int32 = 2
    references :: [2]&Int32 = (&first, &second)
    copied := forward_references(.values = references)
    references[0] = &second
    if copied[0]&!= 40 or references[0]&!= 2 { abort }
    if forward_references(.values = copied)[1]&!= 2 { abort }
    wide :: [300]Int32 = zeroed#(.t: [300]Int32)()
    narrow :: UInt8 = 1
    wide[narrow] = 42
    if wide[1] != 42 { abort }
}
