Owned : Type = (.allocation: Allocation)

Owned init(.allocator: $&Allocator, .fail: Bool) -> (.result: Errable#(.t: Owned, .reasons: (..out_of_memory))) := {
    constructed :: Owned

    allocated ::= allocate(.self = allocator, .size = 1)
    match allocated {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
        ..ok ~ payload {
            if fail {
                deinit(.self = $&payload)
                result = ..error(.reason = ..out_of_memory)
                return
            }
            constructed = (.allocation = ~payload)
            result = ..ok ~constructed
        }
    }
}

Owned deinit(.self: $&Owned) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    success ::= Owned(.allocator = $&allocator_storage, .fail = false)
    match success {
        ..error _ { status_code = 1 }
        ..ok ~ value {
            owned ::= ~value
            deinit(.self = $&owned)
        }
    }
    failure ::= Owned(.allocator = $&allocator_storage, .fail = true)
    match failure {
        ..ok ~ value {
            owned ::= ~value
            deinit(.self = $&owned)
            status_code = 2
        }
        ..error _ {}
    }
}
