Holder : Type = (.reference: $&UInt8)

replace(.holder: $&Holder, .condition: Bool, .reference: $&UInt8) -> () := {
    if condition {
        holder&.reference = reference
        return
    }
    holder&.reference = reference
}

main(.system: System, .condition: Bool = true) -> (.status_code: Int32) := {
    result ::= allocate(.self = system.allocator, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            holder ::= Holder(.reference = allocation.data)
            replace(.holder = $&holder, .condition = condition, .reference = allocation.data)
            observed ::= holder.reference&
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
}
