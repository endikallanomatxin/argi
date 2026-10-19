probe := () -> (.result: Int32) {
    fraction := 0.123123
    if fraction + fraction != 0.246246 { abort }
    single :: Float32 = 16777216.0
    if single + 1.0 != single { abort }
    double :: Float64 = 16777216.0
    if double + 1.0 != 16777217.0 { abort }
    half :: Float16 = 2048.0
    if half + 1.0 != half { abort }
    result = 42
}

fraction := () -> (.result: Float32) {
    result = 0.123123
}

main := () -> (.status_code: Int32) {
    if #run probe() != 42 { abort }
    if #run fraction() != 0.123123 { abort }
    status_code = probe()
}
