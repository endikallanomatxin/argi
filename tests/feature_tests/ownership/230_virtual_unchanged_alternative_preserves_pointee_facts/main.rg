Mutator : Abstract = (
    mutate(.self: $&Self) -> ()
)

Stateful : Type = (
    .reference: $&UInt8
    .counter: Int32
)
Noop : Type = (.marker: UInt8)
Stateful implements Mutator
Noop implements Mutator

mutate(.self: $&Stateful) -> () := {
    self& = (
        .reference = self&.reference,
        .counter = self&.counter + 1,
    )
}

mutate(.self: $&Noop) -> () := {}

register_noop(.value: $&Noop) -> () := {
    _ ::= to_virtual#(.abstract: Mutator)(.value = value)
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            noop ::= Noop(.marker = 0)
            register_noop(.value = $&noop)
            state ::= Stateful(.reference = target.data, .counter = 0)
            if 1 == 1 {
                virtual ::= to_virtual#(.abstract: Mutator)(.value = $&state)
                mutate(.self = $&virtual)
            }
            if state.reference& == 0 {
                status_code = state.counter - 1
            }
        }
    }
}
