Box := (.reference: &Int32)
retarget := (.box: $&Box, .replacement: &Int32) -> () {
    box&.reference = replacement
}
extract := (.box: Box, .replacement: &Int32) -> (.result: &Int32) {
    local ::= box
    retarget(.box = $&local, .replacement = replacement)
    result = local.reference
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    early: Int32 = 7
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    reference ::= extract(.box = Box(&early), .replacement = &early)
    if reference& != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
