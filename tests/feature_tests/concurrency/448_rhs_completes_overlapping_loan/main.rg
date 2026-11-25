Pair: Struct = (.first: Int32, .second: Int32)
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
    alias ::= $&value
    second ::= unwrap_or_abort(async#(write)(.args = (.target = $&value)))
    alias& = finish($&second)
    if value != 7 { abort }
    pair :: Pair = (0, 0)
    field_task ::= unwrap_or_abort(async#(write)(.args = (.target = $&pair.first)))
    pair.first = finish($&field_task)
    if pair.first != 7 { abort }
    values :: [2]Int32 = (0, 0)
    array_task ::= unwrap_or_abort(async#(write)(.args = (.target = $&values[1])))
    values[1] = finish($&array_task)
    if values[1] != 7 { abort }
}
