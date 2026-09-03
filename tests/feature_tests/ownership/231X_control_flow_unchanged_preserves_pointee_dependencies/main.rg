Stateful : Type = (
    .reference: $&UInt8
    .counter: Int32
)

mutate_conditionally(.self: $&Stateful, .condition: Bool) -> () := {
    if condition {
        self& = (
            .reference = self&.reference,
            .counter = self&.counter + 1,
        )
    }
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            state ::= Stateful(.reference = target.data, .counter = 0)
            mutate_conditionally(.self = $&state, .condition = true)
            deinit(.self = $&target)
            if state.reference& == 0 {
                status_code = 0
            }
        }
    }
}
