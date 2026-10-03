_case(.value: CInt) -> (): CFunction(.symbol = "argi_clock_case")
_sleeps() -> (.count: CInt): CFunction(.symbol = "argi_clock_sleeps")
expect_clock_error(.value: Errable#(.t: MonotonicInstant,
        .reasons : (..clock_read_failed, ..out_of_range)),
    .reason : (..clock_read_failed, ..out_of_range)) -> () := {
    if is(.value = value, .variant = ..error) {
        if reason == ..out_of_range {
            if value ..error.reason != ..out_of_range { abort }
        } else {
            if value ..error.reason != ..clock_read_failed { abort }
        }
    } else { abort }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi ::= system.ffi
    assume clock ::= system.clock
    _case(.value = 0)
    first ::= unwrap_or_abort(.value = monotonic_now()).result
    again ::= unwrap_or_abort(.value = monotonic_now()).result
    if first != again or compare(.left = first, .right = again).order != 0 { abort }
    difference ::= unwrap_or_abort(.value = elapsed(.start = first, .end = again)).result
    if nanoseconds(.self = &difference).value != 0 { abort }
    wall ::= unwrap_or_abort(.value = wall_now()).result
    if unix_seconds(.self = &wall).value != -1 or nanoseconds(.self = &wall).value != 750000000 {
        abort
    }
    delay ::= unwrap_or_abort(.value = Duration(.milliseconds = 2)).result
    unwrap_or_abort(.value = sleep(.duration = delay))
    if _sleeps().count != 2 { abort }
    _case(.value = 1)
    expect_clock_error(.value = monotonic_now(), .reason = ..clock_read_failed)
    _case(.value = 2)
    largest ::= unwrap_or_abort(.value = monotonic_now()).result
    interval ::= unwrap_or_abort(.value = elapsed(.start = first, .end = largest)).result
    if nanoseconds(.self = &interval).value != 18446742839141661492 { abort }
    reversed ::= elapsed(.start = largest, .end = first)
    if is(.value = reversed, .variant = ..error) {
        if reversed ..error.reason != ..out_of_range { abort }
    } else { abort }
    _case(.value = 3)
    expect_clock_error(.value = monotonic_now(), .reason = ..out_of_range)
    _case(.value = 4)
    expect_clock_error(.value = monotonic_now(), .reason = ..clock_read_failed)
    _case(.value = 5)
    invalid_wall ::= wall_now()
    if is(.value = invalid_wall, .variant = ..error) {
        if invalid_wall ..error.reason != ..clock_read_failed { abort }
    } else { abort }
    _case(.value = 6)
    failed ::= sleep(.duration = delay)
    if is(.value = failed, .variant = ..error) {
        if failed ..error.reason != ..sleep_failed { abort }
    } else { abort }
    if _sleeps().count != 1 { abort }
    _case(.value = 7)
    unwrap_or_abort(.value = sleep(.duration = Duration(.nanoseconds = 18446744073709551615)))
    if _sleeps().count != 213504 { abort }
    _case(.value = 8)
    unwrap_or_abort(.value = sleep(.duration = Duration(.nanoseconds = 0)))
    if _sleeps().count != 0 { abort }
    _case(.value = 9)
    oldest ::= unwrap_or_abort(.value = wall_now()).result
    if unix_seconds(.self = &oldest).value != -9223372036854775808 or nanoseconds(.self = &oldest).value != 999999999 {
        abort
    }
}
