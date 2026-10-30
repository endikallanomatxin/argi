unsafe_allocation := import ("../../_support/unsafe_allocation")

Mutator#(.Participant: Type): Contract = (
    .mutate : (.self: $&Participant) -> () where {}
)

Stateful := (
    .reference : $&UInt8
    .counter   : Int32
)

Noop := (.marker: UInt8)

implement Mutator#(Stateful) (.mutate = _impl_mutate_Stateful)

implement Mutator#(Noop) (.mutate = _impl_mutate_Noop)

_impl_mutate_Stateful := (.self: $&Stateful) -> () {
    self&.counter = self&.counter + 1
}

_impl_mutate_Noop := (.self: $&Noop) -> () {}

register_noop := (.value: $&Noop) -> () {
    _ ::= to_virtual#(.contract: Mutator)(.value = value)
}

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~target_payload {
            target ::= ~target_payload
            noop ::= Noop(.marker = 0)
            register_noop(.value = $&noop)
            state ::= Stateful(
                .reference = unsafe_allocation.trusted_allocation_byte_rw(
                    .allocation = $&target, .offset = 0
                ).reference
                .counter = 0
            )
            if 1 == 1 {
                virtual ::= to_virtual#(.contract: Mutator)(.value = $&state)
                mutate(.self = $&virtual)
            }
            if state.reference&== 0 {
                status_code = state.counter - 1
            }
        }
    }
}
