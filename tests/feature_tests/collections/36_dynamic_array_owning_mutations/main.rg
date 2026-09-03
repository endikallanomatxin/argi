Tracked : Type = (
    .id: Int32
    .allocation: Allocation
)

first_drops :: Int32 = 0
second_drops :: Int32 = 0
third_drops :: Int32 = 0
fourth_drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    if self&.id == 1 { first_drops = first_drops + 1 }
    if self&.id == 2 { second_drops = second_drops + 1 }
    if self&.id == 3 { third_drops = third_drops + 1 }
    if self&.id == 4 { fourth_drops = fourth_drops + 1 }
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
    array ::= DynamicArray#(.t: Tracked)(.capacity = 4)

    first_result ::= make_tracked(.allocator = system.allocator, .id = 1)
    second_result ::= make_tracked(.allocator = system.allocator, .id = 2)
    third_result ::= make_tracked(.allocator = system.allocator, .id = 3)
    fourth_result ::= make_tracked(.allocator = system.allocator, .id = 4)
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first {
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second {
                    match third_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ third {
                            match fourth_result {
                                ..error _ { status_code = 4 }
                                ..ok ~ fourth {
                                    push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~first)
                                    push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~third)
                                    inserted ::= insert#(.t: Tracked)(.self = $&array, .i = 1, .value = ~second)
                                    if is(.value = inserted, .variant = ..error) {
                                        status_code = 5
                                        return
                                    }

                                    one :: UIntNative = 1
                                    array[one] = ~fourth
                                    if second_drops != 1 {
                                        status_code = 6
                                        return
                                    }

                                    zero :: UIntNative = 0
                                    removed ::= remove#(.t: Tracked)(.self = $&array, .i = zero)
                                    if removed.id != 1 or array.length != 2 {
                                        status_code = 7
                                        return
                                    }
                                    first_remaining ::= dynamic_array_element_ro_pointer#(.t: Tracked)(.array = &array, .offset = 0).pointer
                                    second_remaining ::= dynamic_array_element_ro_pointer#(.t: Tracked)(.array = &array, .offset = 1).pointer
                                    if first_remaining&.id != 4 or second_remaining&.id != 3 {
                                        status_code = 8
                                        return
                                    }

                                    deinit#(.t: Tracked)(.self = $&array)
                                    if first_drops != 0 or second_drops != 1 or third_drops != 1 or fourth_drops != 1 {
                                        status_code = 9
                                        return
                                    }
                                    deinit(.self = $&removed)
                                    if first_drops != 1 or second_drops != 1 or third_drops != 1 or fourth_drops != 1 {
                                        status_code = 10
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
