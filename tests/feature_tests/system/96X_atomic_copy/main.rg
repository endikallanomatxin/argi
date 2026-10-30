main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    cell ::= AtomicUInt32(.initial = 1, .ffi = system.ffi)!!!
    duplicate ::= cell
    store(.self = $&duplicate, .value = 2)
    if load(.self = &cell).value != 1 { abort }
    status_code = 0
}
