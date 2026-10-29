..file_not_found
..permission_denied

read_file := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..file_not_found))
) {
    assume error_tracer

    result = ..error(.reason = ..file_not_found)
}

load_file := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..file_not_found, ..permission_denied))
) {
    assume error_tracer

    value := read_file()!
    result = ..ok value
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    result := load_file()
    if is(.value = result, .variant = ..error) {
        err ::= &result ..error
        if is(.value = err&.reason, .variant = ..file_not_found) {
            status_code = 0
        } else {
            status_code = 1
        }
    } else {
        status_code = 2
    }
}
