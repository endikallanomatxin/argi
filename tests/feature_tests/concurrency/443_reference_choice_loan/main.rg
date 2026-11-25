write := (.target: $&Int32) -> () { target& = 42 }
choose := (.yes: Bool, .left: $&Int32, .right: $&Int32) -> (.result: $&Int32) {
    if yes { result = left } else { result = right }
}
forward := (.target: $&Int32) -> (.result: $&Int32) { result = target }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    a :: Int32 = 0
    b :: Int32 = 0
    selected ::= choose(.yes = a == b, .left = $&a, .right = $&b)
    c :: Int32 = 0
    nested ::= forward(.target = choose(.yes = a == c, .left = selected, .right = $&c))
    task ::= unwrap_or_abort(async#(write)(.args = (.target = nested)))
    unrelated :: Int32 = 0
    unrelated = 1
    _ = unwrap_or_abort(await($&task))
    if a != 42 or unrelated != 1 { abort }
    independent ::= unwrap_or_abort(async#(write)(.args = (.target = $&unrelated)))
    if nested& != 42 { abort }
    _ = unwrap_or_abort(await($&independent))
    if unrelated != 42 { abort }
}
