touch_allocator(
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Int32) := {
    _ ::= allocator
    ok = 0
}

main(.system: System = System()) -> (.status_code: Int32) := {
    status_code = touch_allocator()
}
