Box := (.reference: $&Int32)
write := (.box: Box, .value: Int32) -> () { box.reference& = value }
work := (.input: Int32) -> (.result: Int32) {
    value :: Int32 = 0
    a ::= $&value
    b ::= $&value
    box: Box = (.reference = a)
    write(.box = box, .value = input)
    b& = b& * 2
    result = value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = (.input = 21)))
    result ::= unwrap_or_abort(.value = await($&future))
    if result != 42 { abort }
}
