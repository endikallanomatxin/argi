Borrowing : Type = (.reference: $&UInt8)
Domain : Type = (.marker: UInt8)
Wrapper : Type = (.domain: Domain)

deinit(.self: $&Borrowing) -> () := {}

deinit(.self: $&Domain) -> () := {
    trusted_opaque_release_all(.storage = self)
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    storage_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match storage_result {
                ..error _ { status_code = 2 }
                ..ok ~ storage_payload {
                    storage ::= ~storage_payload
                    if 1 == 1 {
                        wrapper ::= Wrapper(.domain = Domain(.marker = 0))
                        slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = storage.data).reference
                        value :: Borrowing = (.reference = target.data)
                        trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Domain)(.storage = $&wrapper.domain, .destination = slot, .source = ~value)
                        trusted_opaque_drop_owned(.slot = slot)
                    }
                    deinit(.self = $&target)
                    deinit(.self = $&storage)
                    status_code = 0
                }
            }
        }
    }
}
