Container : Type = (
    .inner: Allocation
)

initialize_container(.p: $&Container, .inner: Allocation) -> () := {
    p& = (.inner = ~inner)
}

deinit(.self: $&Container) -> () := {
    deinit(.self = $&self&.inner)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    first_result ::= allocate(.self = $&allocator_storage, .size = 1)
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            container :: Container = (.inner = ~first_payload)
            old ::= &container.inner
            deinit(.self = $&container)

            second_result ::= allocate(.self = $&allocator_storage, .size = 2)
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    initialize_container(.p = $&container, .inner = ~second_payload)
                    fresh ::= &container.inner
                    if fresh&.size == 2 {
                        status_code = 0
                    } else {
                        status_code = 3
                    }
                    deinit(.self = $&container)
                }
            }
        }
    }
}
