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

ProbeExecutor := (.ffi: $&ForeignFunctionInterface, .start: Bool)
implement Executor#(ProbeExecutor) (
    .state = region(self)
    .submit = (.self: $&ProbeExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        pending ::= ~request
        if self&.start {
            submitted ::= execute_inline(.request = ~pending, .ffi = self&.ffi)
            match submitted {
                ..ok ~receipt {}
                ..error _ { abort }
            }
        }
        result = ..error(.reason = ..task_start_failed)
    }
)

check_failed_submission := (.ffi: $&ForeignFunctionInterface, .start: Bool) -> () {
    before ::= drops
    provider ::= ProbeExecutor(ffi, start)
    assume executor ::= Virtual#(Executor)($&provider)
    match async#(make_ticket)(.args = ()) {
        ..ok ~future { abort }
        ..error failure { match failure.reason {
            ..task_start_failed {}
            ..unsupported_task_value { abort }
            ..executor_mismatch { abort }
        } }
    }
    if start {
        if drops != before + 1 { abort }
    } else {
        if drops != before { abort }
    }
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
    check_failed_submission(system.ffi, false)
    check_failed_submission(system.ffi, true)
}
