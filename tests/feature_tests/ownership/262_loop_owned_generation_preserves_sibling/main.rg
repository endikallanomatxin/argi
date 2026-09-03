Pair : Type = (
    .changing: String
    .stable: String
)

deinit(.self: $&Pair, .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&.changing, .allocator = allocator)
    deinit(.self = $&self&.stable, .allocator = allocator)
}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    pair ::= Pair(
        .changing = String(.allocator = system.allocator, .capacity = 1),
        .stable = String(.allocator = system.allocator, .capacity = 1),
    )
    stable_push ::= push_byte(.self = $&pair.stable, .byte = 42, .allocator = system.allocator)
    if is(.value = stable_push, .variant = ..error) {
        return
    }
    stable_data ::= pair.stable.allocation.data
    i :: UIntNative = 0
    while i < 2 {
        pushed ::= push_byte(.self = $&pair.changing, .byte = 65, .allocator = system.allocator)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    stable_data& = 42
    if pair.changing.length != 2 or stable_data& != 42 {
        status_code = 2
        return
    }
    deinit(.self = $&pair, .allocator = system.allocator)
}
