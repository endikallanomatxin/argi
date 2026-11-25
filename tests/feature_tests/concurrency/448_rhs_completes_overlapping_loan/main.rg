write := (.target: $&Int32) -> () { target& = 42 }
finish := (.future: $&Future#(Void)) -> (.result: Int32) {
    _ = unwrap_or_abort(await(future))
    result = 7
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    task ::= unwrap_or_abort(async#(write)(.args = (.target = $&value)))
    value = finish($&task)
    if value != 7 { abort }
}
