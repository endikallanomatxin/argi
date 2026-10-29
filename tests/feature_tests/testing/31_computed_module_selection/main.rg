choose := () -> (.ok: Bool) { ok = true }

main := () -> () { missing_in_main() }

#if choose() {
    test selected := (
        .system       : System,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> !() {
        assume error_tracer

        testing.expect(.condition = true)!
    }
} #else {
    missing := import ("./does_not_exist")
    test discarded := () -> () { missing_in_discarded() }
}
