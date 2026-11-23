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


produce := (.slot: $&?Ticket) -> () {
    ticket ::= make_ticket()
    slot& = ..some(.value = ~ticket)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    {
        slot :: ?Ticket = ..none
        produce($&slot)
        match slot {
            ..none { abort }
            ..some ~payload { if payload.value.value != 42 { abort } }
        }
    }
    if drops != 1 { abort }
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    {
        slot :: ?Ticket = ..none
        submission ::= async#(produce)(.args = (.slot = $&slot))
        match submission {
            ..ok ~future { _ = unwrap_or_abort(await($&future)) }
            ..error failure { match failure.reason {
                ..unsupported_task_value { status_code = 2 }
                ..task_start_failed { status_code = 3 }
                ..executor_mismatch { status_code = 4 }
            }
            return }
        }
    }
    if drops != 2 { abort }
}
