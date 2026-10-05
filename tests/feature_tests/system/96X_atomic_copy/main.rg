main(.system: System) -> !Void = ..ok Void() := {
    cell ::= AtomicUInt32(.initial = 1, .ffi = system.ffi)!
    duplicate ::= cell
    store(.self = $&duplicate, .value = 2)
    if load(.self = &cell).value != 1 { abort }
}
