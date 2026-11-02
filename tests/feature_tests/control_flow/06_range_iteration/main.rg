check_default_step := () -> () {
    sum :: Int32 = 0
    for value in Range(.start = 1, .end = 5) { sum = sum + value }
    if sum != 10 { abort }
}

check_signed_steps := () -> () {
    ascending :: Int32 = 0
    for value in Range(.start = 0, .end = 7, .step = 2) { ascending = ascending + value }
    if ascending != 12 { abort }
    descending :: Int32 = 0
    for value in Range(.start = 5, .end = 0, .step = -2) { descending = descending + value }
    if descending != 9 { abort }
}

check_int64_steps := () -> () {
    start :: Int64 = 1
    finish :: Int64 = 7
    step :: Int64 = 2
    sum :: Int64 = 0
    for value in Range(.start = start, .end = finish, .step = step) { sum = sum + value }
    if sum != 9 { abort }
}

check_default_start := () -> () {
    sum :: Int32 = 0
    for value in Range(.end = 4) { sum = sum + value }
    if sum != 6 { abort }
    stepped :: Int32 = 0
    for value in Range(.end = 7, .step = 2) { stepped = stepped + value }
    if stepped != 12 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    check_default_step()
    check_signed_steps()
    check_int64_steps()
    check_default_start()
}
