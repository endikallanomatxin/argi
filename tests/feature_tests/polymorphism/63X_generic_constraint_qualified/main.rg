library ::= import ("./library")

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    value :: library.Owned = (.value = 7)
    library.accept(.value = &value)
}
