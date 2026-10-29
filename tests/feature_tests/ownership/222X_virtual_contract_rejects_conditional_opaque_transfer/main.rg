unsafe_allocation := import ("../../_support/unsafe_allocation")

OpaqueStorer#(.Participant: Type): Contract = (
    .store : (
        .self: $&Participant, .storage: $&Container, .slot: $&Borrowing, .source: $&Borrowing
    ) -> () where {}
)

Borrowing := (.reference: $&UInt8)

Container := (.marker: UInt8)

Keeping := (.marker: UInt8)

Consuming := (.marker: UInt8)

implement OpaqueStorer#(Keeping) (.store = _impl_store_Keeping)

implement OpaqueStorer#(Consuming) (.store = _impl_store_Consuming)

implement Deinit#(Borrowing) (
    .deinit = (.self: $&Borrowing) -> () {

    }
)

_impl_store_Keeping := (
    .self: $&Keeping, .storage: $&Container, .slot: $&Borrowing, .source: $&Borrowing
) -> () {}

_impl_store_Consuming := (
    .self: $&Consuming, .storage: $&Container, .slot: $&Borrowing, .source: $&Borrowing
) -> () {
    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Container)(
        .storage = storage, .destination = slot, .source = ~source&
    )
}

register_keeping := (.value: $&Keeping) -> () {
    _ ::= to_virtual#(.contract: OpaqueStorer)(.value = value)
}

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    slot_result ::= allocate_bytes(
        .self = $&allocator_storage, .size = size_of(.type = Borrowing)
    )
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~target_payload {
            target ::= ~target_payload
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~slot_payload {
                    slot_storage ::= ~slot_payload
                    slot ::= trusted_mutable_reinterpret_reference#(
                        .from: UInt8, .to: Borrowing
                    )(
                        .base = unsafe_allocation.trusted_allocation_byte_rw(
                            .allocation = $&slot_storage, .offset = 0
                        ).reference
                    ).reference
                    container ::= Container(.marker = 0)
                    keeping ::= Keeping(.marker = 0)
                    register_keeping(.value = $&keeping)
                    implementation ::= Consuming(.marker = 0)
                    virtual ::= to_virtual#(.contract: OpaqueStorer)(.value = $&implementation)
                    source ::= Borrowing(
                        .reference = unsafe_allocation.trusted_allocation_byte_rw(
                            .allocation = $&target, .offset = 0
                        ).reference
                    )
                    store(
                        .self    = $&virtual
                        .storage = $&container
                        .slot    = slot
                        .source  = $&source
                    )
                    deinit(.self = $&target)
                    if source.reference&== 0 {
                        status_code = 0
                    }
                }
            }
        }
    }
}
