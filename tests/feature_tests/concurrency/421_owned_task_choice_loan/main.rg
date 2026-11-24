Target := (..absent, ..present $&Int32)
Owner := (.target: Target)
implement Transferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        match self&.target {
            ..absent {}
            ..present target { target& = 42 }
        }
    }
)
consume := (.owner: Owner) -> () {
    held ::= ~owner
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    target: Target = ..present $&value
    owner ::= Owner(.target = target)
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi))
    _ = unwrap_or_abort(await($&task))
    if value != 42 { abort }
    absent ::= Owner(.target = ..absent)
    empty_task ::= unwrap_or_abort(async_owned#(consume)(.args = (.owner = ~absent), .executor = executor, .ffi = system.ffi))
    value = 1
    _ = unwrap_or_abort(await($&empty_task))
    if value != 1 { abort }
}
