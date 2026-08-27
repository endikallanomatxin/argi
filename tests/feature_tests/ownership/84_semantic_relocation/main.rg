Holder : Type = (.allocation: Allocation)

deinit(.self: $&Holder) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System = System()) -> (.status_code: Int32) := {
    result ::= allocate(.self = system.allocator, .size = 1)
    replacement_result ::= allocate(.self = system.allocator, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            match replacement_result {
                ..error _ {
                    status_code = 1
                }
                ..ok ~ replacement {
                    source :: Holder = (.allocation = ~payload)
                    destination :: Holder = (.allocation = ~replacement)
                    deinit(.self = $&destination)
                    relocate(.source = $&source, .destination = $&destination)
                    fresh ::= &destination.allocation
                    if fresh&.size != 1 {
                        status_code = 2
                        return
                    }
                    deinit(.self = $&destination)
                    status_code = 0
                }
            }
        }
    }
}
