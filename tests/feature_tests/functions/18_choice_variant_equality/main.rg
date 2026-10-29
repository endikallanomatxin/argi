Result: Type = (
    ..ok(.value: Int32),
    ..error(.code: UnicodeScalar),
)

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    value: Result = ..error(.code = 'x')

    if value == ..error {
        if value != ..ok {
            status_code = 0
            return
        }
    }

    status_code = 1
}
