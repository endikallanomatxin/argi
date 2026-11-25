write := (.target: $&Int32) -> () { target& = 42 }
choose := (.yes: Bool, .left: $&Int32, .right: $&Int32) -> (.result: $&Int32) {
    if yes { result = left } else { result = right }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    a :: Int32 = 0
    b :: Int32 = 0
    selected ::= choose(.yes = a == b, .left = $&a, .right = $&b)
    task ::= unwrap_or_abort(async#(write)(.args = (.target = selected)))
    unrelated :: Int32 = 0
    unrelated = 1
    _ = unwrap_or_abort(await($&task))
    if a != 42 or unrelated != 1 { abort }
}
