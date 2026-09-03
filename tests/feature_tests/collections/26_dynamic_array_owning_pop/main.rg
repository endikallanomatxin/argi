Tracked : Type = (
    .id: Int32
    .allocation: Allocation
)

drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    drops = drops + 1
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
    array ::= DynamicArray#(.t: Tracked)(.capacity = 1)
    made ::= make_tracked(.allocator = system.allocator, .id = 7)
    match made {
        ..error _ {
            deinit#(.t: Tracked)(.self = $&array)
            status_code = 1
        }
        ..ok ~ payload {
            item ::= ~payload
            push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~item)
            popped ::= pop#(.t: Tracked)(.self = $&array)

            if popped.id != 7 or array.length != 0 or drops != 0 {
                status_code = 2
                return
            }

            deinit#(.t: Tracked)(.self = $&array)
            if drops != 0 {
                status_code = 3
                return
            }

            deinit(.self = $&popped)
            if drops != 1 {
                status_code = 4
                return
            }
        }
    }
}
