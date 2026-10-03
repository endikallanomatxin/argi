main(.system: System) -> (.status_code: Int32 = 0) := {
    assume clock ::= system.clock
    before ::= unwrap_or_abort(.value = monotonic_now()).result
    delay ::= unwrap_or_abort(.value = Duration(.milliseconds = 2)).result
    unwrap_or_abort(.value = sleep(.duration = delay))
    after ::= unwrap_or_abort(.value = monotonic_now()).result
    interval ::= unwrap_or_abort(.value = elapsed(.start = before, .end = after)).result
    if compare(.left = interval, .right = delay).order < 0 { abort }
    wall ::= unwrap_or_abort(.value = wall_now(.self = system.clock)).result
    if unix_seconds(.self = &wall).value < 0 { abort }
    if nanoseconds(.self = &wall).value >= 1000000000 { abort }
    zero ::= Duration(.nanoseconds = 0)
    unwrap_or_abort(.value = sleep(.duration = zero))
}
