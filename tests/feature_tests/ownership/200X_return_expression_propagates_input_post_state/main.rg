Borrowing : Type = (.reference: $&UInt8)

old_root :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {}

store_and_return(.slot: $&Borrowing, .reference: $&UInt8) -> (.result: UInt8) := {
    slot&.reference = reference
    result = 0
}

store_from_return(.slot: $&Borrowing, .reference: $&UInt8) -> (.result: UInt8) := {
    return store_and_return(.slot = slot, .reference = reference).result
}

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            target ::= ~payload
            holder ::= Borrowing(.reference = $&old_root)
            result ::= store_from_return(.slot = $&holder, .reference = target.data).result
            deinit(.self = $&target)
            observed ::= holder.reference&
            status_code = 0
        }
    }
}
