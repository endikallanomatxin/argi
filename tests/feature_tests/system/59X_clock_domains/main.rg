main(.system: System) -> (.status_code: Int32 = 0) := {
    assume clock ::= system.clock
    wall ::= unwrap_or_abort(.value = wall_now()).result
    instant ::= unwrap_or_abort(.value = monotonic_now()).result
    interval ::= elapsed(.start = wall, .end = instant)
}
