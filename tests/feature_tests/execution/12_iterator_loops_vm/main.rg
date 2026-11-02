main := () -> (.status_code: Int32 = 0) {
    values :: [3]Int32 = (1, 2, 3)
    for $&value in values { value&= value&+ 1 }
    for &value in values { status_code = status_code + value&}
    if status_code != 9 { abort }
    for index in Range(.start = 0, .end = 10) {
        if index < 2 { continue }
        if index > 4 { break }
        for inner in Range(.start = 0, .end = 3) {
            if inner == 0 { continue }
            status_code = status_code + index
        }
    }
    if status_code != 27 { abort }
    for value in values { status_code = status_code + value }
    status_code = status_code + 6
}
