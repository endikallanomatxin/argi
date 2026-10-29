main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    child ::= unwrap_or_abort(
        .value = spawn(.self = system.proc_man, .executable = "test")
    ).result
    value ::= child._handle
    deinit(.self = $&child)
}
