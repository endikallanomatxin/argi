OwningChoice : Type = (
    ..some Allocation
    ..none
)

deinit(.self: $&OwningChoice) -> () := {
}

main(.system: System = System()) -> (.status_code: Int32) := {
    result ::= allocate(.self = system.allocator, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            source :: OwningChoice = ..some ~payload
            destination :: OwningChoice = ..none
            deinit(.self = $&destination)
            relocate(.source = $&source, .destination = $&destination)
            match destination {
                ..none { status_code = 2 }
                ..some ~ allocation {
                    owned ::= ~allocation
                    deinit(.self = $&owned)
                    status_code = 0
                }
            }
        }
    }
}
