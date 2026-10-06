run_main(.system: System) -> !Void = ..ok Void() := {
    now ::= monotonic_now(.self = system.clock)!
    deadline ::= Deadline(.at = now)
    if expired(.self = deadline, .now = now).value == false { abort }
    if nanoseconds(.self = &remaining(.self = deadline, .now = now).value).value != 0 { abort }
    future ::= Deadline(.after = Duration(.nanoseconds = 1000000), .now = now)!
    if expired(.self = future, .now = now).value { abort }
    time_left ::= remaining(.self = future, .now = now).value
    if nanoseconds(.self = &time_left).value != 1000000 { abort }
    source ::= CancellationSource(.ffi = system.ffi)!
    token ::= cancellation_token(.self = &source).token
    if is_cancelled(.self = token).value { abort }
    context ::= CancellationContext(
        .token    = ..some(.value = token)
        .deadline = ..some(.value = deadline)
    )
    match check_cancelled(.self = context, .now = now) {
        ..ok _ { abort } ..error error { if error.reason != ..deadline_exceeded { abort } }
    }
    cancel(.self = $&source)
    cancel(.self = $&source)
    if is_cancelled(.self = token).value == false { abort }
    match check_cancelled(.self = context, .now = now) {
        ..ok _ { abort } ..error error { if error.reason != ..cancelled { abort } }
    }
    empty ::= CancellationContext()
    check_cancelled(.self = empty, .now = now)!
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
