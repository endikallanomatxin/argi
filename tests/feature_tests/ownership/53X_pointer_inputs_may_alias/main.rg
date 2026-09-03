invalidate_then_read(
    .owner_alias: $&Allocation,
    .read_alias: &Allocation,
) -> (.value: UIntNative) := {
    deinit(.self = owner_alias)
    value = read_alias&.size
}

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    allocation ::= ~payload
    invalidate_then_read(
        .owner_alias = $&allocation,
        .read_alias = &allocation,
    )
    status_code = 0
    }
    }
}
