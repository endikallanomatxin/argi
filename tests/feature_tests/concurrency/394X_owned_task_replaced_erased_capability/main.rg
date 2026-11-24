Capability#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: UInt32) where no_access()
)
implement Capability#($$&AtomicUInt32) (
    .observe = (.receiver: $$&AtomicUInt32) -> (.value: UInt32) { value = 1 }
)
implement Capability#($&AtomicUInt32) (
    .observe = (.receiver: $&AtomicUInt32) -> (.value: UInt32) { value = 2 }
)
forward := (.input: Virtual#(Capability)) -> (.output: Virtual#(Capability)) {
    output = input
}
consume := (.input: Virtual#(Capability)) -> (.value: UInt32) {
    value = input.observe().value
}
Slot := (.capability: Virtual#(Capability))
replace := (.slot: $&Slot, .input: Virtual#(Capability)) -> () {
    slot&.capability = input
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    cell ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    local ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    shared ::= $$&cell
    slot :: Slot = Slot(forward(Virtual#(Capability)(shared)).output)
    replace(.slot = $&slot, .input = Virtual#(Capability)($&local))
    view ::= slot.capability
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.input = view), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 1 { abort }
}
