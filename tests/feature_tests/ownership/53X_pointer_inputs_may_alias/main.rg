invalidate_then_read(
    .owner_alias: $&Allocation,
    .read_alias: &Allocation,
) -> (.value: UIntNative) := {
    deinit(.self = owner_alias)
    value = read_alias&.size
}

main(.system: System) -> (.status_code: Int32) := {
    allocation ::= allocate_owned(.self = system.allocator, .size = 1)
    invalidate_then_read(
        .owner_alias = $&allocation,
        .read_alias = &allocation,
    )
    status_code = 0
}
