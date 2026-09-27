main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = size_of(.type = Int32))
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            storage ::= ~payload
            data ::= mutable_reinterpret_reference#(.from: UInt8, .to: Int32)(.base = storage.data).reference
            view ::= array_view#(.t: Int32)(.data = data, .length = 1)
            set_result ::= set(.self = $&view, .index = 1, .value = 42).result
            if is(.value = set_result, .variant = ..error) {
                if is(.value = set_result..error.reason, .variant = ..out_of_bounds) {
                    status_code = 0
                } else {
                    status_code = 2
                }
            } else {
                status_code = 3
            }
            deinit(.self = $&storage)
        }
    }
}
