Holder : Type = (.reference: $&UInt8)

replace(.holder: $&Holder, .condition: Bool, .first: $&UInt8, .second: $&UInt8) -> () := {
    if condition {
        holder&.reference = first
        return
    } else {
        holder&.reference = second
        return
    }
}

main(.system: System, .condition: Bool) -> (.status_code: Int32) := {
    first_result ::= allocate(.self = system.allocator, .size = 1)
    second_result ::= allocate(.self = system.allocator, .size = 1)
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            first ::= ~first_payload
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    second ::= ~second_payload
                    holder ::= Holder(.reference = first.data)
                    replace(.holder = $&holder, .condition = condition, .first = first.data, .second = second.data)
                    deinit(.self = $&first)
                    observed ::= holder.reference&
                    deinit(.self = $&second)
                    status_code = 0
                }
            }
        }
    }
}
