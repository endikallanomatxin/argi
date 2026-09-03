Tracked : Type = (
    .allocation: Allocation
)

deinit(.self: $&Tracked) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation_result ::= allocate(.self = system.allocator, .size = 1)
    match allocation_result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            value ::= Tracked(.allocation = ~payload)
            array ::= DynamicArray#(.t: Tracked)(.capacity = 1)
            push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~value)
            deinit(.self = $&value)
            deinit#(.t: Tracked)(.self = $&array)
        }
    }
}
