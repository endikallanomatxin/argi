probe := () -> (.result: Int32) {
    tracer_storage :: NoopErrorTracer = (.marker = 0)
    tracer_handle ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer_storage)

    fraction := 0.123123
    if fraction + fraction != 0.246246 { abort }
    single :: Float32 = 16777216.0
    if single + 1.0 != single { abort }
    double :: Float64 = 16777216.0
    if double + 1.0 != 16777217.0 { abort }
    half :: Float16 = 2048.0
    if half + 1.0 != half { abort }
    if unwrap_or_abort(.value = parse_float16(.text = "1.5")).result != 1.5 { abort }
    if unwrap_or_abort(.value = parse_float32(.text = "-2.75")).result != -2.75 { abort }
    if unwrap_or_abort(.value = parse_float64(.text = "4.2e1")).result != 42.0 { abort }
    match parse_float32(.text = "1.2.3").result {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..invalid_input { abort } }
    }
    result = 42
}

fraction := () -> (.result: Float32) {
    result = 0.123123
}

half_identity := (.value: Float16) -> (.result: Float16) { result = value }

single_identity := (.value: Float32) -> (.result: Float32) { result = value }

double_identity := (.value: Float64) -> (.result: Float64) { result = value }

main := () -> (.status_code: Int32) {

    if [#run () -> (.value: Int32) { value = probe() }] != 42 { abort }
    if [#run () -> (.value: Float32) { value = fraction() }] != 0.123123 { abort }
    if [#run () -> (.value: Float16) { value = half_identity(.value = 1.5) }] != 1.5 { abort }
    if [#run () -> (.value: Float32) { value = single_identity(.value = 0.123123) }] != 0.123123 {
        abort
    }
    if [
        [#run () -> (.value: Float64) { value = double_identity(.value = 16777217.0) }]
        != 16777217.0
    ] { abort }
    status_code = probe()
}
