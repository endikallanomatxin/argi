invalidate_then_read(
    .allocator: $&Allocator,
    .owner_alias: $&UInt8,
    .read_alias: &UInt8,
) -> (.value: UInt8) := {
    deallocate(.self = allocator, .data = owner_alias, .size = 1)
    value = read_alias&
}

main(.system: System) -> (.status_code: Int32) := {
    byte :: UInt8 = 7
    invalidate_then_read(
        .allocator = system.allocator,
        .owner_alias = $&byte,
        .read_alias = &byte,
    )
    status_code = 0
}
