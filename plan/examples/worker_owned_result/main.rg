drops :: Int32 = 0
Ticket := (.value: Int32)

implement Deinit#(Ticket) (
    .deinit = (.self: $&Ticket) -> () {
        if self&.value != 42 { abort }
        drops = drops + 1
    }
)

make_ticket := () -> (.result: Ticket) {
    result = (.value = 42)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    {
        control ::= make_ticket()
        if control.value != 42 { abort }
    }
    if drops != 1 { abort }
    submission ::= async#(make_ticket)(.args = ())
    match submission {
        ..ok ~future {
            ticket ::= unwrap_or_abort(await($&future))
            if ticket.value != 42 or drops != 1 { abort }
            match await($&future) {
                ..ok ~duplicate { abort }
                ..error failure { match failure.reason {
                    ..already_awaited {}
                    ..task_join_failed { abort }
                } }
            }
        }
        ..error failure {
            match failure.reason {
                ..unsupported_task_value { status_code = 2 }
                ..task_start_failed { status_code = 3 }
                ..executor_mismatch { status_code = 4 }
            }
            return
        }
    }
    if drops != 2 { abort }
    {
        discarded ::= unwrap_or_abort(async#(make_ticket)(.args = ()))
        moved ::= ~discarded
    }
    if drops != 3 { abort }
}
