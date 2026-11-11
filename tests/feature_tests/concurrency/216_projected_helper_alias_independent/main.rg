Box := (.reference: &Int32)
Handle := (.target: $&Box)
choose := (.first: $&Box, .second: $&Box, .select: Bool) -> (.result: $&Box) {
    if select { result = first } else { result = second }
}
select_target := (.handle: Handle) -> (.result: $&Box) { result = handle.target }
retarget := (.box: $&Box, .replacement: &Int32) -> () { box&.reference = replacement }
extract := (.box: Box, .replacement: &Int32, .select: Bool) -> (.result: &Int32) {
    first ::= box
    second ::= box
    handle: Handle = (.target = $&second)
    handle.target = choose(.first = $&first, .second = $&second, .select = select)
    retarget(.box = select_target(handle), .replacement = replacement)
    result = first.reference
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    early: Int32 = 7
    later :: Int32 = 0
    pointer ::= extract(.box = Box(&early), .replacement = &early, .select = true)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    _ = pointer&
    _ = unwrap_or_abort(.value = await($&future))
}
