Tracked : Type = (
    .id: Int32
    .allocation: Allocation
)

first_drops :: Int32 = 0
second_drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    if self&.id == 1 { first_drops = first_drops + 1 }
    if self&.id == 2 { second_drops = second_drops + 1 }
    deinit(.self = $&self&.allocation)
}

make_tracked(.allocator: $&Allocator, .id: Int32) -> (.result: Errable#(.t: Tracked, .reasons: (..out_of_memory))) := {
    allocated ::= allocate(.self = allocator, .size = 1)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            value ::= Tracked(.id = id, .allocation = ~payload)
            result = ..ok ~value
        }
    }
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= DynamicArray#(.t: Tracked)(.capacity = 2)
    first_result ::= make_tracked(.allocator = system.allocator, .id = 1)
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            first ::= ~first_payload
            second_result ::= make_tracked(.allocator = system.allocator, .id = 2)
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    second ::= ~second_payload
                    push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~first)
                    push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~second)
                    popped ::= pop#(.t: Tracked)(.self = $&array)

                    deinit#(.t: Tracked)(.self = $&array)
                    if first_drops != 1 or second_drops != 0 {
                        status_code = 3
                        return
                    }

                    deinit(.self = $&popped)
                    if first_drops != 1 or second_drops != 1 {
                        status_code = 4
                        return
                    }
                }
            }
        }
    }
}
