unsafe_allocation := import ("../../_support/unsafe_allocation")

Rewriter#(.Participant: Type): Contract = (
    .rewrite : (.self: $&Participant, .reference: $&UInt8) -> () where {}
)

Keeping := (.reference: $&UInt8)

Rewriting := (.reference: $&UInt8)

implement Rewriter#(Keeping) (.rewrite = _impl_rewrite_Keeping)

implement Rewriter#(Rewriting) (.rewrite = _impl_rewrite_Rewriting)

_impl_rewrite_Keeping := (.self: $&Keeping, .reference: $&UInt8) -> () {}

_impl_rewrite_Rewriting := (.self: $&Rewriting, .reference: $&UInt8) -> () {
    self&.reference = reference
}

register_keeping := (.value: $&Keeping) -> () {
    _ ::= to_virtual#(.contract: Rewriter)(.value = value)
}

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    old_result ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    target_result ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    match old_result {
        ..error _ { status_code = 1 }
        ..ok ~old_payload {
            old ::= ~old_payload
            keeping :: Keeping = (
                .reference = unsafe_allocation.trusted_allocation_byte_rw(
                    .allocation = $&old, .offset = 0
                ).reference
            )
            register_keeping(.value = $&keeping)
            match target_result {
                ..error _ { status_code = 2 }
                ..ok ~target_payload {
                    target ::= ~target_payload
                    value :: Rewriting = (
                        .reference = unsafe_allocation.trusted_allocation_byte_rw(
                            .allocation = $&old, .offset = 0
                        ).reference
                    )
                    virtual ::= to_virtual#(.contract: Rewriter)(.value = $&value)
                    rewrite(
                        .self      = $&virtual
                        .reference = unsafe_allocation.trusted_allocation_byte_rw(
                            .allocation = $&target, .offset = 0
                        ).reference
                    )
                    deinit(.self = $&target)
                    if value.reference&== 0 {
                        status_code = 0
                    }
                }
            }
        }
    }
}
