main := (.system: System) -> () {
    cell ::= unwrap_or_abort(AtomicUInt32(.ffi = system.ffi))
    shared ::= $$&cell
    _ = shared_load(.self = shared)
}
