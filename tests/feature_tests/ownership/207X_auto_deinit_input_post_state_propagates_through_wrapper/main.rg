Holder : Type = (.reference: $&UInt8)
Observer : Type = (
    .target: $&Holder
    .new_reference: $&UInt8
)

deinit(.self: $&Observer) -> () := {
    self&.target&.reference = self&.new_reference
}

replace_on_exit(.holder: $&Holder, .new_reference: $&UInt8) -> () := {
    observer ::= Observer(.target = holder, .new_reference = new_reference)
}

main(.system: System) -> (.status_code: Int32) := {
    old_result ::= allocate(.self = system.allocator, .size = 1)
    new_result ::= allocate(.self = system.allocator, .size = 1)
    match old_result {
        ..error _ { status_code = 1 }
        ..ok ~ old_payload {
            old ::= ~old_payload
            match new_result {
                ..error _ { status_code = 2 }
                ..ok ~ new_payload {
                    new ::= ~new_payload
                    holder ::= Holder(.reference = old.data)
                    replace_on_exit(.holder = $&holder, .new_reference = new.data)
                    deinit(.self = $&new)
                    observed ::= holder.reference&
                    deinit(.self = $&old)
                    status_code = 0
                }
            }
        }
    }
}
