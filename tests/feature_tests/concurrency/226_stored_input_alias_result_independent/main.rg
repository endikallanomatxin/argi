Box := (.reference: &Int32)
Capture := (.reference: &Int32)
retarget := (.box: $&Box, .replacement: &Int32) -> () { box&.reference = replacement }
extract := (.box: Box, .captured: Capture, .select: Bool) -> (.result: &Int32) {
    first ::= box
    second ::= box
    targets: [2] $&Box = ($&first, $&second)
    retarget(.box = targets[0], .replacement = captured.reference)
    result = first.reference
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    early: Int32 = 7
    later :: Int32 = 0
    pointer ::= extract(.box = Box(&early), .captured = Capture(&early), .select = true)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    _ = pointer&
    _ = unwrap_or_abort(.value = await($&future))
}
