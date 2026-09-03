Tracked : Type = (
    .allocation: Allocation
)

drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    drops = drops + 1
    deinit(.self = $&self&.allocation)
}

take_last(.array: $&DynamicArray#(.t: Tracked)) -> () := {
    popped ::= pop#(.t: Tracked)(.self = array)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            item ::= Tracked(.allocation = ~payload)
            array ::= DynamicArray#(.t: Tracked)(.capacity = 1)
            push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~item)
            take_last(.array = $&array)
            if drops != 1 or array.length != 0 {
                status_code = 2
                return
            }
            deinit#(.t: Tracked)(.self = $&array)
            if drops != 1 {
                status_code = 3
                return
            }
        }
    }
}
