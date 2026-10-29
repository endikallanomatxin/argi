main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume clock ::= system.clock
    wall ::= unwrap_or_abort(.value = wall_now(.self = clock)).result
    instant ::= unwrap_or_abort(.value = monotonic_now(.self = clock)).result
    interval ::= elapsed(.start = wall, .end = instant)
}
