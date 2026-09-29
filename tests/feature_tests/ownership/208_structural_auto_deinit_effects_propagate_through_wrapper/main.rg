unsafe_allocation := import("../../_support/unsafe_allocation")
Borrowing : Type = (.reference: $&UInt8)
Container : Type = (.marker: UInt8)
Domain : Type = (.storage: $&Container)
Wrapper : Type = (.domain: Domain)

deinit(.self: $&Borrowing) -> () := {}

deinit(.self: $&Domain) -> () := {
    trusted_opaque_mark_empty(.storage = self&.storage)
}

release_on_exit(.storage: $&Container) -> () := {
    wrapper ::= Wrapper(.domain = Domain(.storage = storage))
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate(.self = $&allocator_storage, .size = 1)
    storage_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match storage_result {
                ..error _ { status_code = 2 }
                ..ok ~ storage_payload {
                    storage ::= ~storage_payload
                    container ::= Container(.marker = 0)
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&storage, .offset = 0).reference).reference
                    value :: Borrowing = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Container)(.storage = $&container, .destination = slot, .source = ~value)
                    trusted_opaque_drop(.slot = slot)
                    release_on_exit(.storage = $&container)
                    deinit(.self = $&target)
                    deinit(.self = $&storage)
                    status_code = 0
                }
            }
        }
    }
}
