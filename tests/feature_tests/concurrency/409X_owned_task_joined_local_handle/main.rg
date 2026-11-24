Capability#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: UInt32) where { no_access() isolated() }
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
select := (.first: Virtual#(Capability), .second: Virtual#(Capability), .choose_first: Bool) -> (.output: Virtual#(Capability)) {
    if choose_first { output = first } else { output = second }
}
forward_selection := (.first: Virtual#(Capability), .second: Virtual#(Capability), .choice: Bool) -> (.output: Virtual#(Capability)) {
    output = select(.first = first, .second = second, .choose_first = choice).output
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    first ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    second ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    flag ::= load(.self = &first).value == 0
    first_shared ::= $$&first
    second_local ::= $&second
    view ::= forward_selection(.first = Virtual#(Capability)(first_shared), .second = Virtual#(Capability)(second_local), .choice = flag).output
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.input = view), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 1 { abort }
    recover_ordinary(.owner = $&first)
}
