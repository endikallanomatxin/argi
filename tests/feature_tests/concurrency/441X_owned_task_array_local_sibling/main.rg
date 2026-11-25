Capability#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: UInt32) where { no_access() isolated() }
)
implement Capability#($$&AtomicUInt32) (
    .observe = (.receiver: $$&AtomicUInt32) -> (.value: UInt32) { value = 1 }
)
implement Capability#($&AtomicUInt32) (
    .observe = (.receiver: $&AtomicUInt32) -> (.value: UInt32) { value = 2 }
)
consume := (.input: Virtual#(Capability)) -> (.value: UInt32) {
    value = input.observe().value
}
select := (.initial: Virtual#(Capability), .replacement: Virtual#(Capability)) -> (.result: Virtual#(Capability)) {
    items :: [2]Virtual#(Capability) = (initial, initial)
    items[1] = replacement
    result = items[0]
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    cell ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    local ::= unwrap_or_abort(AtomicUInt32(.initial = 0, .ffi = system.ffi))
    shared ::= $$&cell
    view ::= select(.initial = Virtual#(Capability)($&local), .replacement = Virtual#(Capability)(shared))
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.input = view), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 1 { abort }
    recover_ordinary(.owner = $&cell)
}
