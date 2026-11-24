Capability#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: UInt32) where { no_access() isolated() }
)
implement Capability#($$&AtomicUInt32) (
    .observe = (.receiver: $$&AtomicUInt32) -> (.value: UInt32) { value = 1 }
)
Fixed := (.marker: UInt8)
implement ConcurrentAlias#(Fixed) ()
implement Capability#($$&Fixed) (
    .observe = (.receiver: $$&Fixed) -> (.value: UInt32) { value = 3 }
)
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
    second ::= Fixed(0)
    flag ::= load(.self = &first).value == 0
    first_shared ::= $$&first
    second_shared ::= $$&second
    first_view ::= Virtual#(Capability)(first_shared)
    second_view ::= Virtual#(Capability)(second_shared)
    view ::= forward_selection(.first = first_view, .second = second_view, .choice = flag).output
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.input = view), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 1 { abort }
    other_view ::= forward_selection(.first = first_view, .second = second_view, .choice = flag == false).output
    other_task ::= unwrap_or_abort(async_owned#(consume)(.args = (.input = other_view), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&other_task)) != 3 { abort }
    recover_ordinary(.owner = $&first)
    recover_ordinary(.owner = $&second)
}
