Container : Type = (
    .inner: Allocation
)

initialize_container(.p: $&Container, .inner: Allocation) -> () := {
    p& = (.inner = ~inner)
}

deinit(.self: $&Container) -> () := {
    deinit(.self = $&self&.inner)
}

main(.system: System = System()) -> (.status_code: Int32) := {
    first_result ::= allocate(.self = system.allocator, .size = 1)
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            container :: Container = (.inner = ~first_payload)
            old ::= &container.inner
            deinit(.self = $&container)

            second_result ::= allocate(.self = system.allocator, .size = 2)
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    initialize_container(.p = $&container, .inner = ~second_payload)
                    if old&.size == 2 {
                        status_code = 0
                    }
                }
            }
        }
    }
}
