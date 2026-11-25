Pair: CStruct = (.first: Int32, .second: Int32)
write := (.target: $&Int32) -> () { target& = 42 }
choose := (.yes: Bool, .left: $&Int32, .right: $&Int32) -> (.result: $&Int32) {
    if yes { result = left } else { result = right }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    a :: Int32 = 0
    pair :: Pair = (0, 0)
    offset ::= trusted_mutable_reference_offset#(.t: Int32)(.base = $&pair.first, .elements = 1).reference
    selected ::= choose(.yes = a == pair.second, .left = $&a, .right = offset)
    task ::= unwrap_or_abort(async#(write)(.args = (.target = selected)))
    _ = unwrap_or_abort(await($&task))
    if a != 42 { abort }
}
