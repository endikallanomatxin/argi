Pair: Struct = (.first: Int32, .second: Int32)
write := (.target: $&Int32) -> () { target& = 42 }
choose := (.yes: Bool, .left: $&Pair, .right: $&Pair) -> (.result: $&Pair) {
    if yes { result = left } else { result = right }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    a :: Pair = (0, 7)
    b :: Pair = (0, 11)
    selected ::= choose(.yes = a.first == b.first, .left = $&a, .right = $&b)
    field ::= $&selected&.first
    task ::= unwrap_or_abort(async#(write)(.args = (.target = field)))
    b.second = 9
    _ = unwrap_or_abort(await($&task))
    if a.first != 42 or b.second != 9 { abort }
}
