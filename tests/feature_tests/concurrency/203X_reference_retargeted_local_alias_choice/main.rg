Box := (.reference: &Int32)
retarget := (.box: $&Box, .replacement: &Int32) -> () { box&.reference = replacement }
extract := (.box: Box, .replacement: &Int32, .select: Bool) -> (.result: &Int32) {
    first ::= box
    second ::= box
    target ::= $&first
    if select { target = $&second }
    retarget(.box = target, .replacement = replacement)
    result = first.reference
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    early: Int32 = 7
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    pointer ::= extract(.box = Box(&early), .replacement = &later, .select = false)
    _ = pointer&
    _ = unwrap_or_abort(.value = await($&future))
}
