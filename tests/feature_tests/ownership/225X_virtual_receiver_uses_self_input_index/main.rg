unsafe_allocation := #import("../../_support/unsafe_allocation")
Rewriter : Abstract = (
    rewrite(.reference: $&UInt8, .target: $&Self) -> ()
)

Keeping : Type = (.reference: $&UInt8)
Rewriting : Type = (.reference: $&UInt8)
Keeping implements Rewriter
Rewriting implements Rewriter

rewrite(.reference: $&UInt8, .target: $&Keeping) -> () := {}

rewrite(.reference: $&UInt8, .target: $&Rewriting) -> () := {
    target&.reference = reference
}

register_keeping(.value: $&Keeping) -> () := {
    _ ::= to_virtual#(.abstract: Rewriter)(.value = value)
}

main(.system: System) -> (.status_code: Int32) := {
    old_result ::= allocate(.self = system.allocator, .size = 1)
    target_result ::= allocate(.self = system.allocator, .size = 1)
    match old_result {
        ..error _ { status_code = 1 }
        ..ok ~ old_payload {
            old ::= ~old_payload
            keeping :: Keeping = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&old, .offset = 0).reference)
            register_keeping(.value = $&keeping)
            match target_result {
                ..error _ { status_code = 2 }
                ..ok ~ target_payload {
                    target ::= ~target_payload
                    value :: Rewriting = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&old, .offset = 0).reference)
                    virtual ::= to_virtual#(.abstract: Rewriter)(.value = $&value)
                    rewrite(.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference, .target = $&virtual)
                    deinit(.self = $&target)
                    if value.reference& == 0 {
                        status_code = 0
                    }
                }
            }
        }
    }
}
