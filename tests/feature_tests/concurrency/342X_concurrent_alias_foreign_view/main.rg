main := (.system: System) -> () {
    cell ::= unwrap_or_abort(AtomicUInt32(.ffi = system.ffi))
    shared ::= $$&cell
    view ::= trusted_concurrent_view(.shared = shared)
    if load(.self = view).value != 0 { abort }
    recover_ordinary(.owner = $&cell)
}
