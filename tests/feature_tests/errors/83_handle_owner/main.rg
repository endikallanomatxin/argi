..missing

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        self&.value = 0
    }
)

make := (.fail: Bool, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Owner, .reasons: (..missing))
) {
    assume error_tracer

    if fail { result = ..error(.reason = ..missing) } else { result = ..ok(.value = 7) }
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    first ::= make(.fail = false) handle error, value { value = (.value = 9) }
    second ::= make(.fail = true) handle error, value { value = (.value = 9) }
    if first.value != 7 or second.value != 9 { abort }
}
