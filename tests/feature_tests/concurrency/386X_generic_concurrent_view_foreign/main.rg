peek := #(.T: Type) (.shared: $$&T) -> (.view: &T) {
    view = trusted_concurrent_view(.shared = shared)
}

main := (.system: System) -> () {
    cell ::= unwrap_or_abort(AtomicUInt32(.ffi = system.ffi))
    shared ::= $$&cell
    view ::= peek(.shared = shared).view
    if load(.self = view).value != 0 { abort }
    recover_ordinary(.owner = $&cell)
}
