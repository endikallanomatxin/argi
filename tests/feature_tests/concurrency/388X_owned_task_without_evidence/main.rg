Owner := (.value: Int32)
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { if self&.value != 42 { abort } }
)
consume := (.owner: Owner) -> (.value: Int32) {
    held ::= ~owner
    value = held.value
}
main := (.system: System) -> (.status_code: Int32) {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    owner ::= Owner(42)
    started ::= async_owned#(consume)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi)
    match started {
        ..ok ~task {
            outcome ::= await($&task)
            match outcome {
                ..ok value { if value != 42 { abort } status_code = 0 }
                ..error _ { status_code = 12 }
            }
        }
        ..error cause {
            if is(.value = cause.reason, .variant = ..executor_mismatch) { status_code = 13 } else { status_code = 11 }
        }
    }
}
