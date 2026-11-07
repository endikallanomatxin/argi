write := (.value: $&Int32) -> (.result: Int32) { value& = value& + 1 result = value& * 2 }
main := (.system: System) -> () {
    provider ::= InlineExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 20
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    moved ::= ~future
    result ::= unwrap_or_abort(.value = await($&moved))
    if result != 42 or value != 21 { abort }
    match await($&moved) {
        ..ok _ { abort }
        ..error failure { match failure.reason {
            ..already_awaited {}
            ..task_join_failed { abort }
        } }
    }
    {
        discarded ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    }
    if value != 22 { abort }
}
