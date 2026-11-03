pair := (.x: Int32) -> (.first: Int32, .second: Int32) {
    first = x
    second = x + 1
}
nothing := () -> () {}
fail := () -> (.result: Errable#(Int32, (..expected))) {
    result = ..error(.reason = ..expected)
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    first ::= unwrap_or_abort(.value = async#(pair)(.args = (.x = 41)))
    second ::= unwrap_or_abort(.value = async#(nothing)(.args = ()))
    third ::= unwrap_or_abort(.value = async#(fail)(.args = ()))
    output ::= unwrap_or_abort(.value = await($&first))
    if output.first != 41 or output.second != 42 { abort }
    _ = unwrap_or_abort(.value = await($&second))
    failure ::= unwrap_or_abort(.value = await($&third))
    match failure {
        ..ok _ { abort }
        ..error _ {}
    }
    match await($&first) {
        ..ok _ { abort }
        ..error error { match error.reason {
            ..already_awaited {}
            ..task_join_failed { abort }
        } }
    }
    -- Dropping an unobserved Future still joins and releases its native buffers.
    discarded ::= unwrap_or_abort(.value = async#(pair)(.args = (.x = 0)))
}
