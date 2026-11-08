retarget := (.slot: $&&Int32, .replacement: &Int32) -> () {
    slot& = replacement
}
retype_after_retarget := (.base: &Int32, .replacement: &Int32) -> (.result: &UInt32) {
    selected :: &Int32 = base
    retarget(.slot = $&selected, .replacement = replacement)
    result = trusted_reinterpret_reference#(.from: Int32, .to: UInt32)(.base = selected)
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    early: Int32 = 7
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    reference ::= retype_after_retarget(.base = &early, .replacement = &later)
    _ = reference&
    _ = unwrap_or_abort(.value = await($&future))
}
