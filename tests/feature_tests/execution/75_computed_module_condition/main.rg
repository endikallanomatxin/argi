choose := () -> (.ok: Bool) { ok = true }

#if choose() {
    #if choose() {
        main := () -> (.status_code: Int32) { status_code = 42 }
    } #else {
        main := () -> () {
            assume error_tracer ::= $&noop_error_tracer
            missing_nested()!!!
        }
    }
} #else {
    main := () -> () {
        assume error_tracer ::= $&noop_error_tracer
        missing_outer()!!!
    }
}
